module RevisionistV02

#=
Evaluate positions based on piece value and piece square tables
Minimax with alpha beta pruning tree search
=#

using logic
export best_move,evaluate,eval

#define evaluation constants
eval(::Pawn) = Int32(100)
eval(::Queen) = Int32(900)
eval(::Rook) = Int32(500)
eval(::Bishop) = Int32(300)
eval(::Knight) = Int32(300)
const INF = typemax(Int32)

const DEPTH = 2 

mutable struct Logger
    best_score::Int32
    pos_eval::Int32
    branches_cut::Int32
end

Logger(α) = Logger(α,0,0)

"Constant evaluation of stalemate"
eval(::Draw) = Int32(0)
"Constant evaluation of checkmate for white"
eval(::Loss) = INF

"used to negatively weight black positions in evaluation"
get_player(B::Boardstate)::Int8 = ifelse(B.ColourIndex==0, 1, -1)

"Returns score of current position from whites perspective"
function evaluate(board::Boardstate)::Int32
    score = Int32(0)

    moves = generate_moves(board)
    if board.State != Neutral()
        return eval(board.State)
    end

    for (colour,sgn) in zip([White,Black],[+1,-1])
        for type in piecetypes[2:end]
            for pos in identify_locations(board.pieces[colour+val(type)])
                score += sgn*eval(type)
            end
        end
    end
    return score
end

"minimax algorithm, tries to maximise own eval and minimise opponent eval"
function minimax(board,player,α,β,depth,logger)
    if depth == 0
        logger.pos_eval += 1
        return player * evaluate(board)
    else
        moves = generate_moves(board)
        if board.State != Neutral()
            return -player * eval(board.State)
        end

        for move in moves
            make_move!(move,board)
            score = -minimax(board,-player,-β,-α,depth-1,logger)
            #cut when upper bound exceeded
            if score >= β
                logger.branches_cut += 1
                unmake_move!(board)
                return β
            #update alpha when better score is found
            elseif score > α
                α = score
            end
            unmake_move!(board)
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
    logger = Logger(α)

    for move in moves
        make_move!(move,board)
        score = -minimax(board,-player,-β,-α,depth-1,logger)
        if score > α
            best_move = move
            α = score
        end
        unmake_move!(board)
    end
    logger.best_score = α
    return best_move, logger
end

"Evaluates the position to return the best move"
function best_move(board::Boardstate,moves::Vector{Move},depth=DEPTH,logging=false)
    t = time()
    best_move,logger = alpha_beta(board,moves,depth)
    δt = time() - t
    if logging
        @assert best_move != NULLMOVE "Error: Failed to find move better than null move"
        println("Evaluated $(logger.pos_eval) moves, made $(logger.branches_cut) branch cuts.")
        println("Move results in evaluation of $(logger.best_score). Took $δt seconds.")
    end
    return best_move
end

"Wrapper for passing board to best move"
function best_move(position::Boardstate)
    moves = generate_moves(position)
    return best_move(position,moves)
end
end #module