using chessGUI
using logic
import RevisionistV03_02 as bot

const moves = UInt32[21466,
12314,
19412,
17622,
25930,
1063014,
211244,
13356,
174820,
223956,
158689,
8898,
31145,
141962,
18834,
2593,
22950,
9822,
23541,
5645,
30659,
2051,
18210,
83626,
83821,
219171,
27617,
2403,
32169,
3113,
1065350,
8797,
12550,
22563,
172742,
4740,
214508,
185699,
120206,
15542,
31195,
2609,
1068470,
1064574,
13076,
9292,
140492,
216318,
15133,
3113,
4750,
7729,
2196,
23862,
1311310,
28022,
224753,
19702,
206346,
3193,
23706,
2609,
9252,
10862,
2531,
6697,
6179,
11369,
216434]

"tell GUI what to do when button pressed"
function on_button_press!(logicstate,GUIst,moves,counter)
    if counter > 1
        #step backwards in move history
        unmake_move!(logicstate)
        GUIst.position = GUIposition(logicstate)
        counter -= 1
    else
        println("Beginning of game")
    end
end

"tell GUI what to do when mouse pressed"
function on_mouse_press!(evt,square_width,logicstate,GUIst,moves,counter)
    gameover!(logicstate)
    if counter <= length(moves)
        make_move!(moves[counter],logicstate)
        GUIst.position = GUIposition(logicstate)
        counter += 1
    else
        println("End of game")
    end
end

function main()
    FEN = "rn1qkb1r/3ppp1p/b4np1/2pP4/8/2N5/PP2PPPP/R1BQKBNR w KQkq -"

    logicstate = Boardstate(FEN)
    position = GUIposition(logicstate)
    legal_moves = generate_moves(logicstate)
    highlight_moves = []    #visualise legal moves for selected piece
    sq_clicked = -1         #position of mouse click in board coords
    promoting = false

    GUIst = GUIstate(position,legal_moves,highlight_moves,sq_clicked,promoting)
    counter = 1

    main_loop(on_button_press!,on_mouse_press!,logicstate,GUIst,moves,counter)
end
main()