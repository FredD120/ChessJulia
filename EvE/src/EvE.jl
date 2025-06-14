import RevisionistV03_01 as bot1
import RevisionistV03_02 as bot2
using logic
using HDF5

### Test engines against each other ###
#
#Only works for V3 onwards as V1,V2 are not iterative deepening

"Thinking time"
const MAXTIME = 0.01

"Cumulative data from loggers"
mutable struct Tracker
    depth::Int64
    turns::Int64
    q_branch::Float64
end

"Default constructor for tracking data"
Tracker() = Tracker(0,0,0)

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
function evaluate_game!(score,board,side_colour)
    str = ""
    if board.State == Draw()
        score[2] += 1
        str = "Draw"
    else
        if board.Colour == side_colour
            str = "$(turn_colour(Opposite(side_colour))) Wins"
            score[3] += 1 
        else
            str = "$(turn_colour(side_colour)) Wins"
            score[1] += 1
        end
    end
    println(str)
    return str
end

"Play a game bot vs bot - modifies boardstate"
function play_game!(board,player,trackers,move_log)
    ind = 0
    moves = UInt32[]
    sizehint!(moves,100)
    while board.State == Neutral()
        move,log = player.best_move(board,MAXTIME)
        push!(moves,move)
        trackers[ind+1].turns += 1
        
        depth = log.cur_depth
        if log.stopmidsearch
            depth -= 1
        end
        trackers[ind+1].depth += depth
        trackers[ind+1].q_branch += log.cum_nodes ^ (1/depth)

        if move_log
            #println("Playing move: $(UCImove(move)) as $(turn_colour(board.Colour)). Reached depth $(log.cur_depth)")
            println("$move,")
        end

        make_move!(move,board)

        player = player == bot1 ? bot2 : bot1
        ind = (ind + 1) % 2
        gameover!(board)
    end
    return moves
end

"Play a match, both players play a position from both sides - modifies running score totals"
function match!(score,FEN,P1_track,P2_track,log_moves=false)

    game1 = Boardstate(FEN)
    moves1 = play_game!(game1,bot1,[P1_track,P2_track],log_moves)
    outcome1 = evaluate_game!(score,game1,white)

    game2 = Boardstate(FEN)
    moves2 = play_game!(game2,bot2,[P2_track,P1_track],log_moves)
    outcome2 = evaluate_game!(score,game2,black)

    return moves1,moves2,outcome1,outcome2
end

"Get FEN strings and play from those positions from both sides. Report score and average depth searched"
function main()
    #Win, draw, loss of player 1
    score = [0,0,0]
    P1_track = Tracker()
    P2_track = Tracker()

    FENstrings = get_FENs()

    name = "$(bot1)__VS__$(bot2).h5"
    path = "$(dirname(@__DIR__))/results/$name"

    total_time = 0

    h5open(path,"w") do fid
        results = create_group(fid,"results")

        t = time()
        game_num = 0
        for FEN in FENstrings
            game_num += 1
            println("Playing FEN: $FEN")
            moves1,moves2,outcome1,outcome2 = match!(score,FEN,P1_track,P2_track)
            Match = create_group(fid,"match $game_num")
            Match["Game 1 moves"] = moves1
            Match["Game 2 moves"] = moves2
            HDF5.attributes(Match)["Result 1"] = outcome1
            HDF5.attributes(Match)["Result 2"] = outcome2
            HDF5.attributes(Match)["FEN string"] = FEN
        end
        total_time = time() - t

        results["P1 avg depth"] = P1_track.depth/P1_track.turns
        results["P2 avg depth"] = P2_track.depth/P2_track.turns
        results["P1 avg branch factor"] = P1_track.q_branch/P1_track.turns
        results["P2 avg branch factor"] = P2_track.q_branch/P2_track.turns
        results["Final score [W:D:L]"] = score
        results["Thinking time (seconds)"] = MAXTIME
        results["Total time"] = total_time
    end

    println("Player 1 avg depth = $(P1_track.depth/P1_track.turns)")
    println("Player 2 avg depth = $(P2_track.depth/P2_track.turns)")
    println("Player 1 avq branches = $(P1_track.q_branch/P1_track.turns)")
    println("Player 2 avq branches = $(P2_track.q_branch/P2_track.turns)")
    println("Final score was: $score. Took $(total_time) seconds.")
end
main()
#match("rnbqk2r/pp2ppbp/6p1/2p5/2BPP3/2P5/P3NPPP/R1BQK2R b KQkq -",Tracker(),Tracker(),true)
