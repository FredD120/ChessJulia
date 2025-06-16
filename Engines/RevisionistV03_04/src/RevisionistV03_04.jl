module RevisionistV03_04

#=
INHERIT
-> Evaluate positions based on piece value and piece square tables
-> Minimax with alpha beta pruning tree search
-> Iterative deepening
-> Move ordering: 
    -PV

NEW
-> Move ordering: 
    -MVV-LVA 
    -Killer moves
-> Quiescence search
-> Check extension
-> Transposition table
-> Null move pruning
-> Texel tuned PSTs
=#

using logic
using StaticArrays
export best_move,evaluate,eval,side_index,MGweighting,EGweighting,
       score_moves,sort_moves,triangle_number,copy_PV!,MAXDEPTH,
       MINCAPSCORE,MAXMOVESCORE


#define evaluation constants
const INF::Int32 = typemax(Int32) - 1000

#maximum search depth
const MAXDEPTH::UInt8 = UInt8(8)
const MINDEPTH::UInt8 = UInt8(0)

mutable struct SearchInfo
    #Break out early with current best score if OOT
    starttime::Float64
    maxtime::Float64
    #Record best moves from root to leaves for move ordering
    PV::Vector{UInt32}
    PV_len::UInt8
end

"Triangle number for an index starting from zero"
triangle_number(x) = Int(0.5*x*(x+1))

"Constructor for search info struct"
SearchInfo(t_start,t_max) = SearchInfo(t_start,t_max,NULLMOVE*ones(UInt32,triangle_number(MAXDEPTH)),0)

"find index of PV move at current ply"
PV_ind(ply) = Int(ply/2 * (2*MAXDEPTH + 1 - ply))

"Copies line below in triangular PV table"
function copy_PV!(triangle_PV,ply,PV_len,move)
    cur_ind = PV_ind(ply)
    triangle_PV[cur_ind+1] = move
    for i in (cur_ind+1):(cur_ind+PV_len-ply-1)
        triangle_PV[i+1] = triangle_PV[i+MAXDEPTH-ply]
    end
end

"return PV as string"
PV_string(info::SearchInfo) = "$([LONGmove(m) for m in info.PV[1:info.PV_len]])"

mutable struct Logger
    best_score::Int32
    pos_eval::Int32
    cum_nodes::Int32
    cur_depth::UInt8
    stopmidsearch::Bool
    PV::String
end

Logger() = Logger(0,0,0,0,false,"")

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
#Minimum capture score = 199
const MINCAPSCORE = MAXMOVESCORE - 56

"""
Attackers
↓ Q  R  B  N  P <- Victims
K 50 40 30 30 10
Q 51 41 31 31 11
R 52 42 32 32 12
B 53 43 33 33 13
N 53 43 33 33 13
P 55 45 35 35 15
"""
const MV_LV = UInt8[
    50, 40, 30, 30, 10,
    51, 41, 31, 31, 11,
    52, 42, 32, 32, 12,
    53, 43, 33, 33, 13,
    53, 43, 33, 33, 13,
    55, 45, 35, 35, 15]

"lookup value of capture in MVV_LVA table"
MVV_LVA(victim,attacker) = MINCAPSCORE + MV_LV[5*(attacker-1)+victim-1]

"Sorts moves by associated scores"
function sort_moves(moves,scores)
    permute = sortperm(scores,rev=true)
    return moves[permute]
end

"Score moves based on PV, MVV-LVA and killers"
function score_moves(moves,isPV::Bool,PV_move::UInt32=NULLMOVE,killers=[NULLMOVE,NULLMOVE])
    scores = zeros(UInt8,length(moves))

    for (i,move) in enumerate(moves)
        if isPV && move == PV_move
            scores[i] = MAXMOVESCORE

        elseif cap_type(move) > 0
            scores[i] = MVV_LVA(cap_type(move),pc_type(move))
        end
    end
    return scores
end

"minimax algorithm, tries to maximise own eval and minimise opponent eval"
function minimax(board::Boardstate,player::Int8,α,β,depth,ply,onPV::Bool,info::SearchInfo,logger::Logger)
    #If we run out of time, return lower bound on score
    if (time() - info.starttime) > info.maxtime
        logger.stopmidsearch = true
        return α     
    end

    #Evaluate whether we are in a terminal node
    legal_info = gameover!(board)
    if board.State != Neutral()
        logger.pos_eval += 1
        value = eval(board.State,depth)
        return value

    elseif depth <= MINDEPTH
        logger.pos_eval += 1
        value = evaluate(board)
        return player * value
        
    else
        moves = generate_moves(board,legal_info)
        #score and sort moves
        scores = score_moves(moves,onPV,info.PV[ply+1])
        moves = sort_moves(moves,scores)

        for move in moves
            make_move!(move,board)
            score = -minimax(board,-player,-β,-α,depth-1,ply+1,onPV,info,logger)
            unmake_move!(board)

            #only first search is on PV
            onPV = false

            #cut when upper bound exceeded
            if α >= β
                return β
            end

            #update alpha when better score is found
            if score > α
                α = score
                #exact score found, must copy up PV from further down the tree
                copy_PV!(info.PV,ply,info.PV_len,move)
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
    player::Int8 = sgn(board.Colour)
    ply = 0
    #search PV first
    onPV = true 

    #root node is always on PV
    scores = score_moves(moves,onPV,info.PV[ply+1])
    moves = sort_moves(moves,scores)
    
    for move in moves
        make_move!(move,board)
        score = -minimax(board,-player,-β,-α,depth-1,ply+1,onPV,info,logger)
        unmake_move!(board)

        if logger.stopmidsearch
            break
        end

        if score > α
            copy_PV!(info.PV,ply,info.PV_len,move)
            α = score
        end
        onPV = false
    end
    logger.best_score = α
end

"Run minimax search to fixed depth then increase depth until time runs out"
function iterative_deepening(board::Boardstate,T_MAX,logging::Bool)
    moves = generate_moves(board)
    depth = 0
    logger = Logger()
    t_start = time()
    info = SearchInfo(t_start,T_MAX)

    while depth < MAXDEPTH
        #If we run out of time, cancel next iteration
        if (time() - t_start) > 0.2*T_MAX
            break
        end

        depth += 1
        logger.cur_depth = depth
        info.PV_len = depth
        root(board,moves,depth,info,logger)

        logger.PV = PV_string(info)
        if logging
            println("Searched to depth = $(logger.cur_depth). PV so far: "*logger.PV)
        end
        
        if !logger.stopmidsearch
            logger.cum_nodes += logger.pos_eval
            logger.pos_eval = 0
        end
    end
    return info.PV[1], logger
end

"Evaluates the position to return the best move"
function best_move(board::Boardstate,T_MAX,logging=false)
    t = time()
    best_move,logger = iterative_deepening(board,T_MAX,logging)
    δt = time() - t

    best_move != NULLMOVE || error("Failed to find move better than null move")

    if logging
        println("Best move = $(LONGmove(best_move)). Move score = $(logger.best_score). Evaluated $(logger.cum_nodes) positions. Reached depth $((logger.cur_depth)). Time taken: $(round(δt,sigdigits=6))s.)")
        if logger.stopmidsearch
            println("Ran out of time mid search.")
        end
        println("################################################################################################################")
    end
    return best_move,logger
end
end #module