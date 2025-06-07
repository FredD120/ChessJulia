module RevisionistV03_01

#=
INHERIT
-> Evaluate positions based on piece value and piece square tables
-> Minimax with alpha beta pruning tree search

NEW
-> Iterative deepening
-> Quiescence search
-> Check extension
-> Move ordering: 
    -MVV-LVA 
    -Killer moves
    -PVS
-> Transposition table
-> Null move pruning
-> Texel tuned PSTs
=#

using logic
using StaticArrays
export best_move,evaluate,eval,side_index,MGweighting,EGweighting,
       score_moves,sort_moves

#define evaluation constants
const INF::Int32 = typemax(Int32) - 1000

#maximum search depth
const MAXDEPTH::UInt8 = UInt8(8)
const MINDEPTH::UInt8 = UInt8(0)

mutable struct SearchInfo
    #How far away from root
    ply::UInt8
    #Break out early with current best score if OOT
    starttime::Float64
    maxtime::Float64
    #Record best move at root for move ordering
    best_mv::UInt32
end

SearchInfo(t_start,t_max) = SearchInfo(UInt8(0),t_start,t_max,NULLMOVE)

mutable struct Logger
    best_score::Int32
    pos_eval::Int32
    terminal::Int32
    branches_cut::Dict{UInt8,UInt64}
    evalδt::Float64
    movegenδt::Float64
    moveorderδt::Float64
    makeδt::Float64
    terminalδt::Float64
    cur_depth::UInt8
    stopmidsearch::Bool
end

Logger() = Logger(0,0,0,Dict{UInt8,UInt64}(),0,0,0,0,0,0,false)

"Make dictionary of branch cuts more readable"
function unpack(D::Dict{UInt8,UInt64})
    vec = zeros(Int,length(D))
    for (key,val) in D
        vec[key] = val
    end
    vec
end

"Macro to construct timing calls that log time spent in functions"
macro log_time(logger_field_expr, code_expr)
    # Generate unique variable names to avoid clashes
    t_start = gensym(:t_start)
    result = gensym(:result)
    logger = gensym(:logger_var)

    logger_var_expr = logger_field_expr.args[1] 
    field_name_expr = logger_field_expr.args[2] 

    quote
        $(logger) = $(esc(logger_var_expr))

        $(t_start) = time()
        $(result) = $(esc(code_expr)) # Evaluate the expression being timed
        current_time = getproperty($(logger), $(esc(field_name_expr)))
        setproperty!($(logger), $(esc(field_name_expr)), current_time + (time() - $(t_start)))
        $(result) # Return the result of the expression
    end
end

"Constant evaluation of stalemate"
eval(::Draw,depth) = Int32(0)
"Constant evaluation of being checkmated (favour quicker mates)"
eval(::Loss,depth) = -INF - depth

#number of pieces left when endgame begins
const EGBEGIN = 12

"If more than EGBEGIN+2 pieces lost, set to 0. Between 0 and EGBEGIN+2 pieces lost, decrease linearly from 1 to 0"
function MGweighting(pc_remaining)::Float32 
    pc_lost = 24 - pc_remaining
    grad = -1/(EGBEGIN+2)
    weight = 1 + grad*pc_lost
    return max(0,weight)
end

"If more than EGBEGIN+2 pieces remaining, set to 0. Between EGBEGIN+2 and 2 remaining increase linearly to 1"
function EGweighting(pc_remaining)::Float32 
    grad = -1/EGBEGIN
    weight = 1 + grad*(pc_remaining-2)
    return max(0,weight)
end

"Returns score of current position from whites perspective"
function evaluate(board::Boardstate)::Int32
    num_pieces = count_pieces(board.pieces)
    score = board.PSTscore[1]*MGweighting(num_pieces) + board.PSTscore[2]*EGweighting(num_pieces)
    
    return Int32(round(score))
end

#Score of PV/TT move = 255
const MAXMOVESCORE = typemax(UInt8)
#Minimum capture score = 200
const MINCAPSCORE = MAXMOVESCORE - 55

"Sorts moves by associated scores"
function sort_moves(moves,scores)
    permute = sortperm(scores,rev=true)
    return moves[permute]
end

"Score moves based on PV, MVV-LVA and killers"
function score_moves(moves,cur_best::UInt32,isPV::Bool)
    scores = zeros(UInt8,length(moves))

    for (i,move) in enumerate(moves)
        if isPV && move == cur_best
            scores[i] = MAXMOVESCORE
        end
    end
    return scores
end

"minimax algorithm, tries to maximise own eval and minimise opponent eval"
function minimax(board,player,α,β,depth,info::SearchInfo,logger::Logger)
    #If we run out of time, return lower bound on score
    if (time() - info.starttime) > info.maxtime
        logger.stopmidsearch = true
        return α     
    end

    #Evaluate whether we are in a terminal node
    legal_info = @log_time logger.terminalδt gameover!(board)
    if board.State != Neutral()
        logger.terminal += 1
        value = @log_time logger.evalδt eval(board.State,depth)
        return value

    elseif depth <= MINDEPTH
        logger.pos_eval += 1
        value = @log_time logger.evalδt evaluate(board)
        return player * value
        
    else
        moves = @log_time logger.movegenδt generate_moves(board,legal_info)
        for move in moves
            t = time()
            make_move!(move,board)
            logger.makeδt += time() - t

            info.ply += 1
            score = -minimax(board,-player,-β,-α,depth-1,info,logger)

            t = time()
            unmake_move!(board)
            logger.makeδt += time() - t
            info.ply -= 1

            #update alpha when better score is found
            α = max(α,score)
            #cut when upper bound exceeded
            if α >= β
                get!(logger.branches_cut,depth,0)
                logger.branches_cut[depth] += 1
                return β
            end
        end
        return α
    end
end

"Root of minimax search. Deals in moves not scores"
function root(board,moves,depth,info::SearchInfo,logger::Logger)
    #whites current best score
    α = -INF 
    #whites current worst score (blacks best score)
    β = INF
    player = sgn(board.Colour)

    #root node is always on PV
    scores = @log_time logger.moveorderδt score_moves(moves,info.best_mv,true)
    moves = @log_time logger.moveorderδt sort_moves(moves,scores)
    
    for move in moves
        make_move!(move,board)
        info.ply += 1
        score = -minimax(board,-player,-β,-α,depth-1,info,logger)
        unmake_move!(board)
        info.ply -= 1

        if logger.stopmidsearch
            break
        end

        if score > α
            info.best_mv = move
            α = score
        end
    end
    logger.best_score = α
end

"root of minimax with alpha beta pruning"
function iterative_deepening(board::Boardstate,T_MAX,logging::Bool)
    moves = generate_moves(board)
    depth = 0
    logger = Logger()
    t_start = time()
    info = SearchInfo(t_start,T_MAX)
    best_move = NULLMOVE

    while depth <= MAXDEPTH
        #If we run out of time, cancel next iteration
        if (time() - t_start) > 0.2*T_MAX
            break
        end

        depth += 1
        logger.cur_depth = depth
        root(board,moves,depth,info,logger)

        if logging
            println("Searched to depth = $(logger.cur_depth). Best move so far: [$(UCImove(info.best_mv))]")
        end
        #we are not currently searching full PV so not safe to adopt move from partial search
        if !logger.stopmidsearch
            best_move = info.best_mv
        end
    end
    return best_move, logger
end

"Evaluates the position to return the best move"
function best_move(board::Boardstate,T_MAX,logging=false)
    t = time()
    best_move,logger = iterative_deepening(board,T_MAX,logging)
    δt = time() - t

    best_move != NULLMOVE || error("Failed to find move better than null move")

    if logging
        println("Move score = $(logger.best_score). Evaluated $(logger.pos_eval) moves. Reached depth $((logger.cur_depth))")
        if logger.stopmidsearch
            println("Ran out of time mid search.")
        end

        println("Time: $(round(δt,sigdigits=6))s. Evaluation: $(Int(round(100*logger.evalδt/δt)))%. Movegen: $(Int(round(100*logger.movegenδt/δt)))%. Move ordering: $(Int(round(100*logger.moveorderδt/δt)))%. Make/Unmake: $(Int(round(100*logger.makeδt/δt)))%. Gameover: $(Int(round(100*logger.terminalδt/δt)))%.")
        println("Reached $(logger.terminal) terminal nodes. Branch cuts: $(unpack(logger.branches_cut)).")
        println("################################################################################################################")
    end
    return best_move,logger
end
end #module