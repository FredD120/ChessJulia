module RevisionistV02

#=
Evaluate positions based on piece value and piece square tables
Minimax with alpha beta pruning tree search
=#

using logic
using StaticArrays
export best_move,evaluate,eval,side_index,MGweighting,EGweighting

#define evaluation constants
const INF::Int32 = typemax(Int32) - 1000

#maximum search depth
const DEPTH::UInt8 = 4 

mutable struct Logger
    best_score::Int32
    pos_eval::Int32
    terminal::Int32
    branches_cut::Vector{Int32}
    evaltime::Float64
    movegentime::Float64
end

Logger(depth) = Logger(0,0,0,zeros(depth),0,0)

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

"minimax algorithm, tries to maximise own eval and minimise opponent eval"
function minimax(board,player,α,β,depth,logger)
    t = time()
    moves = generate_moves(board)
    logger.movegentime += time() - t
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
function alpha_beta(board::Boardstate,moves::Vector{UInt32},depth::UInt8)
    best_move = NULLMOVE
    #whites current best score
    α = -INF 
    #whites current worst score (blacks best score)
    β = INF
    player = sgn(board.Colour)
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
function best_move(board::Boardstate,moves::Vector{UInt32},depth::UInt8=DEPTH,logging=false)
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
        println("################################################################################################################")
    end
    return best_move
end

"Find best move silently but return logger"
function best_move(position::Boardstate)
    moves = generate_moves(position)
    best_move,logger = alpha_beta(position,moves,DEPTH)
    return best_move,logger
end
end #module