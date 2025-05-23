module RevisionistV02

#=
Evaluate positions based on piece value and piece square tables
Minimax with alpha beta pruning tree search
=#

using logic
using StaticArrays
export best_move,evaluate,eval

#define evaluation constants
eval(::Pawn) = Float32(100)
eval(::Queen) = Float32(900)
eval(::Rook) = Float32(500)
eval(::Bishop) = Float32(300)
eval(::Knight) = Float32(300)
const INF::Int32 = typemax(Int32) - 1000

const DEPTH = 4 

function get_PST(type)
    data = Vector{Float32}()
    data_str = readlines("$(dirname(@__DIR__))/PST/$(type).txt")
    for d in data_str
        push!(data, parse(Float32,d))
    end   
    return data
end

const PawnPST::SVector{64,Float32} = get_PST("pawn")

PST(::Piece, index) = Float32(0)
PST(::Pawn, index) = PawnPST[index]

"Index into PST"
side_index(::white, ind) = ind

"Reverse rank order to access PSTs as black"
side_index(::black, ind) = 8*(7 - rank(ind)) + file(ind)

mutable struct Logger
    best_score::Int32
    pos_eval::Int32
    terminal::Int32
    branches_cut::Vector{Int32}
    evaltime::Float64
end

Logger(depth) = Logger(0,0,0,zeros(depth),0)

"Constant evaluation of stalemate"
eval(::Draw,depth) = Int32(0)
"Constant evaluation of being checkmated (favour quicker mates)"
eval(::Loss,depth) = -INF - depth

"used to negatively weight black positions in evaluation"
get_player(B::Boardstate)::Int8 = ifelse(B.ColourIndex==0, 1, -1)

"Returns score of current position from whites perspective. Value calculated as a Float then rounded to an Int"
function evaluate(board::Boardstate)::Int32
    score = Float32(0)

    for (colour,sgn) in zip([white(),black()],[+1,-1])
        for type in piecetypes[2:end]
            for pos in identify_locations(board.pieces[val(colour)+val(type)])
                score += sgn*eval(type)
                score += PST(type,side_index(colour,pos))
            end
        end
    end
    return Int32(round(score))
end

"minimax algorithm, tries to maximise own eval and minimise opponent eval"
function minimax(board,player,α,β,depth,logger)
    moves = generate_moves(board)
    if board.State != Neutral()
        logger.terminal += 1
        t = time()
        value = eval(board.State,depth)
        logger.evaltime += time() - t
        return value

    elseif depth == 0
        logger.pos_eval += 1
        t = time()
        value = evaluate(board)
        logger.evaltime += time() - t
        return player * value
    else
        for move in moves
            make_move!(move,board)
            score = -minimax(board,-player,-β,-α,depth-1,logger)
            unmake_move!(board)

            #update alpha when better score is found
            α = max(α,score)
            #cut when upper bound exceeded
            if α >= β
                logger.branches_cut[depth] += 1
                return β
            end
        end
        return α
    end
end

"root of minimax with alpha beta pruning"
function alpha_beta(board::Boardstate,moves::Vector{Move},depth)
    best_move = NULLMOVE
    #whites current best score
    α = -INF 
    #whites current worst score (blacks best score)
    β = INF
    player = get_player(board)
    logger = Logger(depth)

    for move in moves
        make_move!(move,board)
        score = -minimax(board,-player,-β,-α,depth-1,logger)
        unmake_move!(board)

        if score > α
            best_move = move
            α = score
        end
    end
    logger.best_score = α
    return best_move, logger
end

"Evaluates the position to return the best move"
function best_move(board::Boardstate,moves::Vector{Move},depth=DEPTH,logging=false)
    t = time()
    best_move,logger = alpha_beta(board,moves,depth)
    δt = time() - t

    if best_move == NULLMOVE
        if logging
            println("Failed to find move better than null move")
        end
        return moves[1]
    end
    if logging
        println("Evaluated $(logger.pos_eval) moves, made $(logger.branches_cut) branch cuts.")
        if logger.evaltime > 0
            println("$(Int(round(logger.pos_eval/logger.evaltime))) Evaluations per second . Represents $(Int(round(100*logger.evaltime/δt)))% of total time  ")
        else
            println("Zero time spent on eval")
        end
        println("Reached $(logger.terminal) terminal nodes. Move results in evaluation of $(logger.best_score). Took $δt seconds.")
    end
    return best_move
end

"Wrapper for passing board to best move"
function best_move(position::Boardstate)
    moves = generate_moves(position)
    return best_move(position,moves)
end
end #module