import RevisionistV03_01 as bot1
import RevisionistV03_02 as bot2
using logic

### Test engines against each other ###
#
#Only works for V3 onwards as V1,V2 are not iterative deepening

const MAXTIME = 0.01

function play_game!(board,P1,P2)
    player = P1
    while board.State == Neutral()
        move,log = player.best_move(board,MAXTIME)

        println("Playing move: $(UCImove(move))")
        make_move!(move,board)

        player = player == P1 ? P2 : P1
    end
end

function match(FEN,log_moves=false)
    #Win, draw, loss of player 1
    score = [0,0,0]
    
    game1 = Boardstate(FEN)
    play_game!(game1,bot1,bot2)

    println(game1.State)

    game2 = Boardstate(FEN)
    play_game!(game1,bot2,bot1)
    println(game2.State)

    return score
end

function main()
    score = [0,0,0]
    FEN = "r1bq1rk1/pp2ppbp/2n2np1/2pp4/5P2/1P2PN2/PBPPB1PP/RN1Q1RK1 w - -"

    score = score .+ match(FEN)
    println(score)
end
main()