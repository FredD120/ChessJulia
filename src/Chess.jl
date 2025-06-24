using chessGUI
using logic
import RevisionistV04_01 as bot

const BOTTIME = 1.0

"update gui based on mouse click to indicate legal moves"
function mouse_clicked(mouse_pos,legal_moves,kingpos)
    highlight = []
    for move in legal_moves
        if (flag(move) == KCASTLE) | (flag(move) == QCASTLE)
            if kingpos == mouse_pos
                if flag(move) == KCASTLE
                    push!(highlight,kingpos+2)
                else
                    push!(highlight,kingpos-2)
                end
            end
        elseif from(move) == mouse_pos
            push!(highlight,to(move))
        end
    end
    return highlight
end

function promote_move!(logicstate,GUIst,index,legal_moves,BOT)
    promotype = [PROMQUEEN,PROMROOK,PROMBISHOP,PROMKNIGHT]

    moveID = findfirst(i->flag(i)==promotype[index],legal_moves)
    GUImove!(legal_moves[moveID],logicstate,GUIst,BOT)
end

"If pawn is promoting, highlight possible promotions to display on GUI"
function promote_squares(prompos,Whitemove,posit)
    inc = ifelse(Whitemove==0,8,-8)
    highlight = []
    Ptype = [Queen,Rook,Bishop,Knight]
    for i in 0:3
        pos = prompos+i*inc
        push!(highlight,pos)
        posit[pos+1] = Ptype[i+1]+Whitemove*black
    end
    return highlight,posit
end

"update logic with move made and return true if trying to promote"
function move_clicked!(logicstate,GUIst,move_from,mouse_pos,kingpos,legal_moves,BOT)
    for move in legal_moves
        if (to(move) == mouse_pos) & (from(move) == move_from)
            if (flag(move) == PROMQUEEN)|(flag(move) == PROMROOK)|(flag(move) == PROMBISHOP)|(flag(move) == PROMKNIGHT)
                return true
            else
                GUImove!(move,logicstate,GUIst,BOT)
                return false
            end
        #check for castling moves
        elseif move_from == kingpos
            if (mouse_pos == move_from + 2) & (flag(move) == KCASTLE)
                GUImove!(move,logicstate,GUIst,BOT)
                return false
            elseif (mouse_pos == move_from - 2) & (flag(move) == QCASTLE)
                GUImove!(move,logicstate,GUIst,BOT)
                return false
            end
        end
    end
end

"Prints the winner and returns true if game is over"
function check_win(logicstate::Boardstate)
    gameover!(logicstate)
    if logicstate.State != Neutral()
        if logicstate.State == Draw()
            println("Game over: Draw")
        elseif Whitesmove(logicstate.Colour)
            println("Game over: Black wins")
        else
            println("Game over: White wins")
        end
        return true
    else
        return false
    end
end
    
"Encapsulates behaviour of PvP vs PvE"
function GUImove!(move,board,GUIst,vsBOT)
    make_move!(move,board)
    if vsBOT && !check_win(board)
        #JIT compile
        if GUIst.counter == 0
            botmove,log = bot.best_move(board,0.5)
            GUIst.counter += 1
        end
        botmove,log = bot.best_move(board,BOTTIME,true)
        make_move!(botmove,board)
    end
end

"tell GUI what to do when button pressed"
function on_button_press!(logicstate,GUIst,vsBOT)
    #step backwards in move history
    unmake_move!(logicstate)
    if vsBOT #need to undo bots turn as well
        unmake_move!(logicstate) 
    end

    #update positions of pieces in GUI representation
    GUIst.position = GUIposition(logicstate)
    #generate new set of moves
    GUIst.legal_moves = generate_moves(logicstate)
    #reset square clicked on to nothing
    GUIst.highlight_moves = []
    GUIst.sq_clicked = -1
end

"tell GUI what to do when mouse pressed"
function on_mouse_press!(evt,square_width,logicstate,GUIst,vsBOT)
    mouse_evt = getproperty(evt,:button)
    xpos = getproperty(mouse_evt,:x)
    ypos = getproperty(mouse_evt,:y)
    mouse_pos = board_coords(xpos,ypos,square_width)
    kingpos = trailing_zeros(ally_pieces(logicstate)[King])

    if (length(GUIst.highlight_moves) > 0)
        if mouse_pos in GUIst.highlight_moves
            if GUIst.promoting
                index = findfirst(i->i==mouse_pos,GUIst.highlight_moves)
                promote_move!(logicstate,GUIst,index,GUIst.legal_moves,vsBOT)
                GUIst.promoting = false
            else
                #make move in logic then update GUI to reflect new board
                GUIst.promoting = move_clicked!(logicstate,GUIst,GUIst.sq_clicked,mouse_pos,kingpos,GUIst.legal_moves,vsBOT)
            end

            if GUIst.promoting
                hi_mv,pos = promote_squares(mouse_pos,logic.ColID(logicstate.Colour),GUIst.position)
                GUIst.highlight_moves = hi_mv
                GUIst.position = pos
            else
                #update positions of pieces in GUI representation
                GUIst.position = GUIposition(logicstate)
                #generate new set of moves
                GUIst.legal_moves = generate_moves(logicstate)
                GUIst.highlight_moves = []
            end
        else
            #reset square clicked on to nothing
            GUIst.highlight_moves = []
        end
        GUIst.sq_clicked = -1
    else
        GUIst.highlight_moves = mouse_clicked(mouse_pos,GUIst.legal_moves,kingpos)
        GUIst.sq_clicked = mouse_pos
    end
    check_win(logicstate)
end

function main()
    #SDL_Quit()
    FEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

    vsbot = true
    logicstate = Boardstate(FEN)
    position = GUIposition(logicstate)
    legal_moves = generate_moves(logicstate)

    highlight_moves = []    #visualise legal moves for selected piece
    sq_clicked = -1         #position of mouse click in board coords
    promoting = false
    counter = 0

    GUIst = GUIstate(position,legal_moves,highlight_moves,sq_clicked,promoting,counter)
    
    main_loop(on_button_press!,on_mouse_press!,logicstate,GUIst,vsbot)
end
main()