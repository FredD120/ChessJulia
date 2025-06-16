using chessGUI
using logic
using HDF5

"tell GUI what to do when button pressed"
function on_button_press!(logicstate,GUIst,args...)
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
function on_mouse_press!(evt,square_width,logicstate,GUIst,moves,PVs,scores)
    gameover!(logicstate)
    if GUIst.counter <= length(moves)
        make_move!(moves[GUIst.counter],logicstate)
        println("Score = $(scores[GUIst.counter]). PV = $(PVs[GUIst.counter])")

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
    PVs = String[]
    scores = Int[]

    h5open(path,"r") do fid
        match = fid["match $match_num"]
        FEN = attrs(match)["FEN string"]
        moves = read(match,"Game $game_num moves")

        P1_PVs = read(match,"Game $game_num P1 PV")
        P2_PVs = read(match,"Game $game_num P2 PV")

        P1_evals = read(match,"Game $game_num P1 Eval")
        P2_evals = read(match,"Game $game_num P2 Eval")

        if game_num == 1
            PVs = collect(Iterators.flatten(zip(P1_PVs,P2_PVs)))
            scores = collect(Iterators.flatten(zip(P1_evals,P2_evals)))
        elseif game_num == 2
            PVs = collect(Iterators.flatten(zip(P2_PVs,P1_PVs)))
            scores = collect(Iterators.flatten(zip(P2_evals,P1_evals)))
        end 
    end

    if FEN != ""
        return FEN, moves, PVs, scores
    else
        error("Failed to find game")
    end
end

function main()
    FEN,moves,PVs,scores = fetch_game("RevisionistV03_03","RevisionistV03_05",21,2)

    logicstate = Boardstate(FEN)
    position = GUIposition(logicstate)
    legal_moves = generate_moves(logicstate)
    highlight_moves = []    #visualise legal moves for selected piece
    sq_clicked = -1         #position of mouse click in board coords
    promoting = false
    counter = 1

    GUIst = GUIstate(position,legal_moves,highlight_moves,sq_clicked,promoting,counter)

    main_loop(on_button_press!,on_mouse_press!,logicstate,GUIst,moves,PVs,scores)
end
main()