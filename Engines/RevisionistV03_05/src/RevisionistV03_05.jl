module RevisionistV03_05

#=
INHERIT
-> Evaluate positions based on piece value and piece square tables
-> Minimax with alpha beta pruning tree search
-> Iterative deepening
-> Move sorting: 
    -PV
    -MVV-LVA 

NEW
-> Move ordering: 

    -Killer moves
-> Quiescence search
-> Check extension
-> Transposition table
-> Null move pruning
-> Texel tuned PSTs

TO THINK ABOUT
#Sometimes we incorrectly think we are getting mated when we run out of time
#What can we do if we have to cancel a search part way through?
=#

using logic
using StaticArrays
export best_move,evaluate,eval,side_index,MGweighting,EGweighting,
       triangle_number,copy_PV!,MAXDEPTH,MINCAPSCORE,MAXMOVESCORE,
       Logger,swap!,next_best!,score_moves!

#define evaluation constants
const INF::Int32 = typemax(Int32) - 1000

#maximum search depth
const MAXDEPTH::UInt8 = UInt8(12)
const MINDEPTH::UInt8 = UInt8(0)

mutable struct SearchInfo
    #Break out early with current best score if OOT
    starttime::Float64
    maxtime::Float64
    #Record best moves from root to leaves for move ordering
    PV::Vector{UInt32}
    PV_len::UInt8
    nodes_since_time::UInt16
end

"Triangle number for an index starting from zero"
triangle_number(x) = Int(0.5*x*(x+1))

"Constructor for search info struct"
SearchInfo(t_start,t_max) = SearchInfo(t_start,t_max,NULLMOVE*ones(UInt32,triangle_number(MAXDEPTH)),0,0)

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
const MAXMOVESCORE::UInt8 = typemax(UInt8)
#Minimum capture score = 199
const MINCAPSCORE::UInt8 = MAXMOVESCORE - 56

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
MVV_LVA(victim,attacker)::UInt8 = MINCAPSCORE + MV_LV[5*(attacker-1)+victim-1]

"swap the positions of two entries in a vector"
function swap!(list,ind1,ind2)
    temp = list[ind1]
    list[ind1] = list[ind2]
    list[ind2] = temp
end

"iterates through scores and swaps next best score and move to top of list"
function next_best!(moves,cur_ind)
    len = length(moves)
    if cur_ind < len
        cur_best_score = 0
        cur_best_ind = cur_ind

        for i in cur_ind:len
            score_i = score(moves[i])
            if score_i > cur_best_score
                cur_best_score = score_i
                cur_best_ind = i 
            end
        end
        swap!(moves,cur_ind,cur_best_ind)
    end
end

"Score moves based on PV, MVV-LVA and killers"
function score_moves!(moves,isPV::Bool,PV_move::UInt32=NULLMOVE,killers=[NULLMOVE,NULLMOVE])
    for (i,move) in enumerate(moves)
        if isPV && move == PV_move
            moves[i] = set_score(move,MAXMOVESCORE)

        elseif iscapture(move)
            moves[i] = set_score(move,MVV_LVA(cap_type(move),pc_type(move)))
        end
    end
end

"minimax algorithm, tries to maximise own eval and minimise opponent eval"
function minimax(board::Boardstate,player::Int8,α,β,depth,ply,onPV::Bool,info::SearchInfo,logger::Logger)
    #reduce number of sys calls
    info.nodes_since_time += 1
    if info.nodes_since_time > 500
        #If we run out of time, return lower bound on score
        if (time() - info.starttime) > info.maxtime*0.95
            logger.stopmidsearch = true
            return α     
        end
        info.nodes_since_time = 0
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
        score_moves!(moves,onPV,info.PV[ply+1])

        for i in eachindex(moves)
            next_best!(moves,i)
            move = moves[i]

            make_move!(move,board)
            score = -minimax(board,-player,-β,-α,depth-1,ply+1,onPV,info,logger)
            unmake_move!(board)

            #only first search is on PV
            onPV = false

            #update alpha when better score is found
            if score > α
                #cut when upper bound exceeded
                if score >= β
                    return β
                end
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
    #search PV first, only if it exists
    onPV = true 

    #root node is always on PV
    score_moves!(moves,onPV,info.PV[ply+1])

    for i in eachindex(moves)
        next_best!(moves,i)
        move = moves[i]

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
    return α
end

"Run minimax search to fixed depth then increase depth until time runs out"
function iterative_deepening(board::Boardstate,T_MAX,verbose::Bool)
    moves = generate_moves(board)
    depth = 0
    logger = Logger()
    t_start = time()
    info = SearchInfo(t_start,T_MAX)
    bestscore = 0

    while depth < MAXDEPTH
        #If we run out of time, cancel next iteration
        if (time() - t_start) > 0.2*T_MAX
            break
        end

        depth += 1
        logger.cur_depth = depth
        info.PV_len = depth
        bestscore = root(board,moves,depth,info,logger)

        logger.PV = PV_string(info)
        if verbose
            println("Searched to depth = $(logger.cur_depth). PV so far: "*logger.PV)
        end
        
        if !logger.stopmidsearch
            logger.cum_nodes += logger.pos_eval
            logger.pos_eval = 0
            logger.best_score = bestscore 
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