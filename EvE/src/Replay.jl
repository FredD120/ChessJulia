using chessGUI
using logic
using HDF5

"tell GUI what to do when button pressed"
function on_button_press!(logicstate,GUIst,moves)
    if GUIst.counter > 1
        #step backwards in move history
        unmake_move!(logicstate)
        GUIst.position = GUIposition(logicstate)
        GUIst.counter -= 1
    else
        println("Beginning of game")
    end
end

"tell GUI what to do when mouse pressed"
function on_mouse_press!(evt,square_width,logicstate,GUIst,moves)
    gameover!(logicstate)
    if GUIst.counter <= length(moves)
        make_move!(moves[GUIst.counter],logicstate)
        GUIst.position = GUIposition(logicstate)
        GUIst.counter += 1
    else
        println("End of game")
    end
end

"Fetch a game between two bots from an HDF5 file and return moves played and starting FEN string"
function fetch_game(E1,E2,match_num,game_num)
    name = "$(E1)__VS__$(E2).h5"
    path = "$(dirname(@__DIR__))/results/$name"

    FEN = ""
    moves = UInt32[]

    h5open(path,"r") do fid
        match = fid["match $match_num"]
        FEN = attrs(match)["FEN string"]
        moves = read(match,"Game $game_num moves")
    end

    if FEN != ""
        return FEN, moves
    else
        error("Failed to find game")
    end
end

function main()
    FEN,moves = fetch_game("RevisionistV03_01","RevisionistV03_02",1,1)

    logicstate = Boardstate(FEN)
    position = GUIposition(logicstate)
    legal_moves = generate_moves(logicstate)
    highlight_moves = []    #visualise legal moves for selected piece
    sq_clicked = -1         #position of mouse click in board coords
    promoting = false
    counter = 0

    GUIst = GUIstate(position,legal_moves,highlight_moves,sq_clicked,promoting,counter)

    main_loop(on_button_press!,on_mouse_press!,logicstate,GUIst,moves)
end
main()