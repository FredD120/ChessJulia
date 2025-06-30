import RevisionistV03_08 as bot1
import RevisionistV04_01 as bot2
using logic
using HDF5

### Test engines against each other ###
#
#Only works for V3 onwards as V1,V2 are not iterative deepening

"Thinking time"
const MAXTIME = 0.2

"Cumulative data from loggers for whole match"
mutable struct Tracker
    depth_P1::Int64
    turns_P1::Int64
    branch_P1::Float64

    depth_P2::Int64
    turns_P2::Int64
    branch_P2::Float64

    PV_P1_G1::Vector{String}
    eval_P1_G1::Vector{Int}
    PV_P1_G2::Vector{String}
    eval_P1_G2::Vector{Int}

    PV_P2_G1::Vector{String}
    eval_P2_G1::Vector{Int}
    PV_P2_G2::Vector{String}
    eval_P2_G2::Vector{Int}

    moves_G1::Vector{UInt32}
    moves_G2::Vector{UInt32}
    outcome_G1::String
    outcome_G2::String
end

"constructor for tracker. info is filled in after game"
Tracker() = Tracker(0,0,0,0,0,0,
            [],[],[],[],[],[],[],[],
            [],[],"","")

"constructor for analysis data from engine"
function Analysis(log::Union{bot1.Logger,bot2.Logger}) 
    prinV = ""
    try prinV = log.PV
    catch;end

    (prinV,log.best_score)
end

"Report whose turn it is"
turn_colour(ID) = ifelse(ID==0,"White","Black")

"Fetch start positions from file"
function get_FENs()
    FENs = String[]
    path = "$(dirname(@__DIR__))/initial_positions.txt"
    positions = readlines(path)

    for pos in positions
        push!(FENs,split(pos," id ")[1])
    end
    return FENs
end

"Figure out which bot won and update score accordingly"
function evaluate_game!(score,board,P1_side)
    str = ""
    if board.State == Draw()
        score[2] += 1
        str = "Draw"
    else
        if P1_side
            str = "Player 1 loses"
            score[3] += 1 
        else
            str = "Player 1 Wins"
            score[1] += 1
        end
    end
    println(str)
    return str
end

"JIT compile bot1 and bot2"
function warmup()
    FEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
    board = Boardstate(FEN)
    move1 = bot1.best_move(board,2.0)
    move2 = bot2.best_move(board,2.0)
end

"Play a game bot vs bot - modifies boardstate"
function play_game!(board,player,log_moves::Bool)
    ind = 0
    moves = UInt32[]
    sizehint!(moves,100)

    P1_PV = String[]
    P2_PV = String[]
    P1_eval = Int[]
    P2_eval = Int[]

    PVs = [P1_PV,P2_PV]
    Evals = [P1_eval,P2_eval]
    trk_turns = [0,0]
    trk_depth = [0,0]
    trk_branch = [0.0,0.0]
    while board.State == Neutral()
        move,log = player.best_move(board,MAXTIME)
        push!(moves,move)

        trk_turns[ind+1] += 1

        PV,eval = Analysis(log)
        push!(PVs[ind+1],PV)
        push!(Evals[ind+1],eval)
        
        depth = log.cur_depth
        if log.stopmidsearch
            depth -= 1
        end
        trk_depth[ind+1] += depth
        trk_branch[ind+1] += log.cum_nodes ^ (1/depth)

        if log_moves
            #println("Playing move: $(UCImove(move)) as $(turn_colour(board.Colour)). Reached depth $(log.cur_depth)")
            println("$move,")
        end

        make_move!(move,board)

        player = player == bot1 ? bot2 : bot1
        ind = (ind + 1) % 2
        gameover!(board)
    end
    return moves,PVs,Evals,trk_turns,trk_depth,trk_branch,player
end

"Play a match, both players play a position from both sides - modifies running score totals"
function match!(score,FEN,log_moves=false)
    track = Tracker()

    game1 = Boardstate(FEN)
    moves,PVs,Evals,trk_turns,trk_depth,trk_branch,final_player = play_game!(game1,bot1,log_moves)
    P1_last = bot1 == final_player
    outcome = evaluate_game!(score,game1,P1_last)

    track.depth_P1 += trk_depth[1]
    track.turns_P1 += trk_turns[1]
    track.branch_P1 += trk_branch[1]

    track.depth_P2 += trk_depth[2]
    track.turns_P2 += trk_turns[2]
    track.branch_P2 += trk_branch[2]

    track.PV_P1_G1 = PVs[1]
    track.PV_P2_G1 = PVs[2]
    track.eval_P1_G1 = Evals[1]
    track.eval_P2_G1 = Evals[2]

    track.moves_G1 = moves
    track.outcome_G1 = outcome

    game2 = Boardstate(FEN)
    moves,PVs,Evals,trk_turns,trk_depth,trk_branch,final_player = play_game!(game2,bot2,log_moves)
    P1_last = bot1 == final_player
    outcome = evaluate_game!(score,game2,P1_last)

    track.depth_P1 += trk_depth[2]
    track.turns_P1 += trk_turns[2]
    track.branch_P1 += trk_branch[2]

    track.depth_P2 += trk_depth[1]
    track.turns_P2 += trk_turns[1]
    track.branch_P2 += trk_branch[1]

    track.PV_P1_G2 = PVs[2]
    track.PV_P2_G2 = PVs[1]
    track.eval_P1_G2 = Evals[2]
    track.eval_P2_G2 = Evals[1]

    track.moves_G2 = moves
    track.outcome_G2 = outcome

    return track
end

"Get FEN strings and play from those positions from both sides. Report score and average depth searched"
function main()
    #Win, draw, loss of player 1
    score = [0,0,0]

    FENstrings = get_FENs()

    name = "$(bot1)__VS__$(bot2).h5"
    path = "$(dirname(@__DIR__))/results/$name"

    trackers = Vector{Tracker}(undef,length(FENstrings))
    t = time()
    num = 0
    total = length(FENstrings)
    Threads.@threads for (game_num,FEN) in collect(enumerate(FENstrings))
        warmup()
        println("Playing FEN: $FEN")
        trackers[game_num] = match!(score,FEN)
        num += 1
        println("$num/$total")
    end
    total_time = time() - t

    P1_track_depth = 0
    P1_track_turns = 0
    P1_track_branch = 0

    P2_track_depth = 0
    P2_track_turns = 0
    P2_track_branch = 0

    h5open(path,"w") do fid
        results = create_group(fid,"results")

        for (game_num,track) in enumerate(trackers)
            Match = create_group(fid,"match $game_num")
            Match["Game 1 moves"] = track.moves_G1
            Match["Game 2 moves"] = track.moves_G2

            Match["Game 1 P1 Eval"] = track.eval_P1_G1
            Match["Game 1 P2 Eval"] = track.eval_P2_G1
            Match["Game 1 P1 PV"] = track.PV_P1_G1
            Match["Game 1 P2 PV"] = track.PV_P2_G1

            Match["Game 2 P1 Eval"] = track.eval_P1_G2
            Match["Game 2 P2 Eval"] = track.eval_P2_G2
            Match["Game 2 P1 PV"] = track.PV_P1_G2
            Match["Game 2 P2 PV"] = track.PV_P2_G2

            HDF5.attributes(Match)["Result 1"] = track.outcome_G1
            HDF5.attributes(Match)["Result 2"] = track.outcome_G2
            HDF5.attributes(Match)["FEN string"] = FENstrings[game_num]

            P1_track_depth += track.depth_P1
            P1_track_turns += track.turns_P1
            P1_track_branch += track.branch_P1

            P2_track_depth += track.depth_P2
            P2_track_turns += track.turns_P2
            P2_track_branch += track.branch_P2
        end

        results["P1 avg depth"] = P1_track_depth/P1_track_turns
        results["P2 avg depth"] = P2_track_depth/P2_track_turns
        results["P1 avg branch factor"] = P1_track_branch/P1_track_turns
        results["P2 avg branch factor"] = P2_track_branch/P2_track_turns
        results["Final score [W:D:L]"] = score
        results["Thinking time (seconds)"] = MAXTIME
        results["Total time"] = total_time
    end

    println("Player 1 avg depth = $(P1_track_depth/P1_track_turns)")
    println("Player 2 avg depth = $(P2_track_depth/P2_track_turns)")
    println("Player 1 avq branches = $(P1_track_branch/P1_track_turns)")
    println("Player 2 avq branches = $(P2_track_branch/P2_track_turns)")
    println("Final score was: $score. Took $(total_time) seconds.")
end
main()
#match("rnbqk2r/pp2ppbp/6p1/2p5/2BPP3/2P5/P3NPPP/R1BQK2R b KQkq -",Tracker(),Tracker(),true)
