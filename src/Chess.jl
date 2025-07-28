using chessGUI
using logic
import Scylla as Sc
import RevisionistV04_01 as bot
import RevisionistV03_08 as bot2

const BOTTIME = 1.0
const verbose = true
const two_bots = false

function make!(move,board::Boardstate,engine::EngineState) 
    logic.make_move!(move,board)
    Scylla.make_move!(move,engine.board)
end

make!(move,board::Boardstate,engine::Nothing) = logic.make_move!(move,board)

function unmake!(board::Boardstate,engine::EngineState) 
    logic.unmake_move!(board)
    Scylla.unmake_move!(engine.board)
end

unmake!(board::Boardstate,engine::Nothing) = logic.unmake_move!(board)

best(board::Boardstate,engine::Nothing,local_bot) = local_bot.best_move(board,BOTTIME,verbose)[1]

best(board::Boardstate,engine::EngineState,bot) = Scylla.best_move(engine,verbose,max_T=BOTTIME)[1]

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

function promote_move!(game::Game,GUIst,index,legal_moves,BOT)
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
function move_clicked!(game::Game,GUIst,move_from,mouse_pos,kingpos,legal_moves,BOT)
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
function GUImove!(move,game::Game,GUIst,vsBOT)
    make!(move,game.logic,game.engine)
    if vsBOT && !check_win(board)
        botmove = best(game.board,game.engine,bot)
        make!(botmove,game.logic,game.engine)
    end
end

"tell GUI what to do when button pressed"
function on_button_press!(game::Game,GUIst,vsBOT)
    #step backwards in move history
    unmake!(game.board,game.engine)
    if vsBOT #need to undo bots turn as well
        unmake!(game.board,game.engine) 
    end

    #update positions of pieces in GUI representation
    GUIst.position = GUIposition(game.board)
    #generate new set of moves
    GUIst.legal_moves = generate_moves(game.board)
    #reset square clicked on to nothing
    GUIst.highlight_moves = []
    GUIst.sq_clicked = -1
end

function BotvsBot(game::Game,GUIst)
    move = best(game.board,game.engine,bot2)
    make!(move,game.board,game.engine)
    check_win(game.board)
    move2 = best(game.board,game.engine,bot)
    make!(move2,game.board,game.engine)
    GUIst.position = GUIposition(game.board)
end

"tell GUI what to do when mouse pressed"
function on_mouse_press!(evt,square_width,game::Game,GUIst,vsBOT)
    if two_bots==true && vsBOT == true
        BotvsBot(game::Game,GUIst)
        return nothing
    end

    mouse_evt = getproperty(evt,:button)
    xpos = getproperty(mouse_evt,:x)
    ypos = getproperty(mouse_evt,:y)
    mouse_pos = board_coords(xpos,ypos,square_width)
    kingpos = trailing_zeros(ally_pieces(game.board)[King])

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

"JIT compile bot"
function warmup(game::Game)
    move = best(game.board,game.engine,bot)
    if two_bots
     move = best(game.board,game.engine,bot2)
    end
end

function main()
    #SDL_Quit()
    FEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
    #FEN = "8/8/R7/pppppppk/5R1R/8/8/7K b - - 1 1"
    vsbot = false

    logicstate = Boardstate(FEN)
    engine = nothing#EngineState(FEN)
    game = Game(logicstate,engine)

#    if vsbot
#        warmup(game)
#    end

    position = GUIposition(logicstate)
    legal_moves = generate_moves(logicstate)

    highlight_moves = []    #visualise legal moves for selected piece
    sq_clicked = -1         #position of mouse click in board coords
    promoting = false
    counter = 0

    GUIst = GUIstate(position,legal_moves,highlight_moves,sq_clicked,promoting,counter)
    
    main_loop(on_button_press!,on_mouse_press!,game,GUIst,vsbot)
end
main()