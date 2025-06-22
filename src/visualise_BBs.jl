using logic
using chessGUI
   
"take in square pos from 0 to 63 and translate to pixel position of centre of square"
function pixel_coords(i,sq_width)
    xpos = (i) % 8
    ypos = (i - xpos) / 8
    return xpos*sq_width, ypos*sq_width
end

"take in pixel coordinates and return which chess square it is on (0-indexed)"
function board_coords(xpos,ypos,sq_width)
    x = Int((xpos - (xpos % sq_width))/sq_width)
    y = Int((ypos - (ypos % sq_width))/sq_width)
    return x + y*8
end

"converts a list of positions to a bitboard"
function array_to_BB(arr)
    BB = UInt64(0)
    for a in arr
        BB |= (UInt64(1)<<a)
    end
    return BB
end

"convert a bitboard to visualise in GUI"
function get_GUI_moves(BB,pieceID)
    pos_list = logic.identify_locations(BB)
    GUIboard = zeros(Integer,64)
    for pos in pos_list
        GUIboard[pos+1] = pieceID
    end
    return GUIboard
end

"convert a bitboard to visualise in GUI"
function set_GUI(GUI,BB,pieceID)
    pos_list = logic.identify_locations(BB)
    for pos in pos_list
        GUI[pos+1] = pieceID
    end
    return GUI
end

function remove!(a, item)
    deleteat!(a, findall(x->x==item, a))
end

"update gui based on mouse click to indicate legal moves for sliders/pawns"
function on_mouse_press!(evt,square_width,logicstate,GUIst)
    mouse_evt = getproperty(evt,:button)
    xpos = getproperty(mouse_evt,:x)
    ypos = getproperty(mouse_evt,:y)
    mouse_pos = board_coords(xpos,ypos,square_width)

    #hijack promoting Bool to decide whether to place pieces or blockers
    if  GUIst.promoting
        if count(i->(i==mouse_pos),GUIst.highlight_moves) == 0
            push!(GUIst.highlight_moves,mouse_pos)
        else
            remove!(GUIst.highlight_moves,mouse_pos)
        end
    else
        ## Display pawn moves using bitshifting
        pawns = array_to_BB(GUIst.highlight_moves) 
        rshift_mask = UInt64(0xFEFEFEFEFEFEFEFE)
        lshift_mask = UInt64(0x7F7F7F7F7F7F7F7F)

        pawn_push = pawns << 8
        pawn_left = (pawn_push >> 1) & lshift_mask
        pawn_right = (pawn_push << 1) & rshift_mask

        GUIst.position = UInt8[0x09, 0x00, 0x00, 0x00, 0x00, 0x0a, 0x0b, 0x00, 0x00, 0x03, 0x04, 0x00, 0x0c, 0x07, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x09, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x04, 0x00, 0x03]
        #GUIst.position = set_GUI(GUIboard,pawn_left,val(Bishop()))
        #GUIst.position = set_GUI(GUIboard,pawn_right,val(Rook()))

        #Display rook and bishop moves using magic BBs 
        #blockers = array_to_BB(GUIst.highlight_moves) 
        #move_BB = logic.sliding_attacks(logic.BishopMagics[mouse_pos+1],blockers)

        #GUIst.position = get_GUI_moves(514,val(logic.Bishop()))
    end
end

"define behaviour on button press"
function on_button_press!(logicstate,GUIst)
    #flip state
    GUIst.promoting = !GUIst.promoting
end

function main()
    #SDL_Quit()
    FEN = "8/8/8/8/8/8/8/8 w - - 0 1"
    
    logicstate = Boardstate(FEN)
    position = GUIposition(logicstate)
    legal_moves = UInt32[]

    highlight_moves = []    #visualise legal moves for selected piece
    sq_clicked = -1         #position of mouse click in board coords
    promoting = false
    counter = 0

    GUIst = GUIstate(position,legal_moves,highlight_moves,sq_clicked,promoting,counter)

    main_loop(on_button_press!,on_mouse_press!,logicstate,GUIst)
end
main()

