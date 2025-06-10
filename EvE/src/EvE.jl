import RevisionistV03_01 as bot1
import RevisionistV03_02 as bot2
using logic

### Test engines against each other ###
#
#Only works for V3 onwards as V1,V2 are not iterative deepening

const MAXTIME = 0.01

mutable struct Tracker
    depth::Int64
    turns::Int64
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
function evaluate_game!(score,board,side_colour)
    if board.State == Draw()
        score[2] += 1
        println("Draw")
    else
        if board.Colour == side_colour
            println("$(turn_colour(Opposite(side_colour))) Wins")
            score[3] += 1 
        else
            println("$(turn_colour(side_colour)) Wins")
            score[1] += 1
        end
    end
end

"Play a game bot vs bot"
function play_game!(board,player,trackers,move_log)
    ind = 0
    while board.State == Neutral()
        move,log = player.best_move(board,MAXTIME)
        trackers[ind+1].turns += 1

        if log.stopmidsearch
            trackers[ind+1].depth += log.cur_depth - 1
        else
            trackers[ind+1].depth += log.cur_depth 
        end
        if move_log
            #println("Playing move: $(UCImove(move)) as $(turn_colour(board.Colour)). Reached depth $(log.cur_depth)")
            println("$move,")
        end

        make_move!(move,board)

        player = player == bot1 ? bot2 : bot1
        ind = (ind + 1) % 2
        gameover!(board)
    end
end

"Play a match, both players play a position from both sides"
function match(FEN,P1_track,P2_track,log_moves=false)
    #Win, draw, loss of player 1
    score = [0,0,0]
   
    game1 = Boardstate(FEN)
    play_game!(game1,bot1,[P1_track,P2_track],log_moves)
    evaluate_game!(score,game1,white)

    game2 = Boardstate(FEN)
    play_game!(game2,bot2,[P2_track,P1_track],log_moves)
    evaluate_game!(score,game2,black)

    return score
end

"Get FEN strings and play from those positions from both sides. Report score and average depth searched"
function main()
    score = [0,0,0]
    P1_track = Tracker(0,0)
    P2_track = Tracker(0,0)

    FENstrings = get_FENs()

    t = time()
    for FEN in FENstrings
        println("Playing FEN: $FEN")
        score = score .+ match(FEN,P1_track,P2_track)
    end

    println("Player 1 avg depth = $(P1_track.depth/P1_track.turns)")
    println("Player 2 avg depth = $(P2_track.depth/P2_track.turns)")
    println("Final score was: $score. Took $(time()-t) seconds.")
end
main()

#match("rn1qkb1r/3ppp1p/b4np1/2pP4/8/2N5/PP2PPPP/R1BQKBNR w KQkq -",Tracker(0,0),Tracker(0,0),true)