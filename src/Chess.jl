using SimpleDirectMediaLayer
using SimpleDirectMediaLayer.LibSDL2
using logic
import RevisionistV03_01 as bot
#using libpng_jll

"initialise window and renderer in SDL"
function startup(WIDTH=1000,HEIGHT=1000)
    SDL_GL_SetAttribute(SDL_GL_MULTISAMPLEBUFFERS, 16)
    SDL_GL_SetAttribute(SDL_GL_MULTISAMPLESAMPLES, 16)

    @assert SDL_Init(SDL_INIT_EVERYTHING) == 0 "error initializing SDL: $(unsafe_string(SDL_GetError()))"

    win = SDL_CreateWindow("Game", SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED, WIDTH, HEIGHT, SDL_WINDOW_SHOWN)
    SDL_SetWindowResizable(win, SDL_TRUE)

    renderer = SDL_CreateRenderer(win, -1, SDL_RENDERER_ACCELERATED | SDL_RENDERER_PRESENTVSYNC)
    return win,renderer
end

"create texture from surface and delete surface"
function texture!(surface,renderer)
    tex = SDL_CreateTextureFromSurface(renderer, surface)
    if tex == C_NULL
        error("Failed to create texture")
    end

    SDL_FreeSurface(surface)
    return tex
end

"retrieve texture from file"
function get_texture(renderer,path,name)
    surface = IMG_Load("$(path)$(name).png")
    @assert surface != C_NULL "Error loading image: $(unsafe_string(SDL_GetError()))"

    return texture!(surface,renderer)
end

"loads chess pieces from file and creates vector of pointers to textures"
function load_pieces(renderer)
    
    filepath = "$(pwd())/ChessPieces/"
    texture_vec = Vector{Ptr{SDL_Texture}}(undef,12)

    texture_vec[ColourPieceID(white,King())] = get_texture(renderer,filepath,"WhiteKing")
    texture_vec[ColourPieceID(white,Queen())] = get_texture(renderer,filepath,"WhiteQueen")
    texture_vec[ColourPieceID(white,Pawn())] = get_texture(renderer,filepath,"WhitePawn")
    texture_vec[ColourPieceID(white,Bishop())] = get_texture(renderer,filepath,"WhiteBishop")
    texture_vec[ColourPieceID(white,Knight())] = get_texture(renderer,filepath,"WhiteKnight")
    texture_vec[ColourPieceID(white,Rook())] = get_texture(renderer,filepath,"WhiteRook")
    texture_vec[ColourPieceID(black,King())] = get_texture(renderer,filepath,"BlackKing")
    texture_vec[ColourPieceID(black,Queen())] = get_texture(renderer,filepath,"BlackQueen")
    texture_vec[ColourPieceID(black,Pawn())] = get_texture(renderer,filepath,"BlackPawn")
    texture_vec[ColourPieceID(black,Bishop())] = get_texture(renderer,filepath,"BlackBishop")
    texture_vec[ColourPieceID(black,Knight())] = get_texture(renderer,filepath,"BlackKnight")
    texture_vec[ColourPieceID(black,Rook())] = get_texture(renderer,filepath,"BlackRook")

    return texture_vec
end

"takes in position in pixel coords returns true if square is dark colour"
is_dark_sq(x,y,sq_width) = ((x-1) ÷ sq_width + (y-1) ÷ sq_width) % 2 == 0

"return flat colour"
const_colour(x,y,c) = SDL_Color(c[1], c[2], c[3], c[4])

"takes in position in pixel coords return colours in chessboard pattern"
function chessboard(x,y,sq_width,brn,crm)
    brown = SDL_Color(brn[1], brn[2], brn[3], brn[4])  # Brown
    cream = SDL_Color(crm[1], crm[2], crm[3], crm[4])  # Cream

    # Checkerboard pattern
    if is_dark_sq(x,y,sq_width)
        return brown
    else
        return cream
    end
end

"create and apply colour to surface"
function colour_surface(f,renderer,width,args...)
    # Create surface (32-bit RGBA format)
    surface = SDL_CreateRGBSurfaceWithFormat(0, width, width, 32, SDL_PIXELFORMAT_RGBA32)
    if surface == C_NULL
        error("Failed to create surface")
    end

    SDL_LockSurface(surface) != 0 && error("Failed to lock surface")

    # Get pixel data as a Ptr{UInt32} (since format is RGBA32)
    pixels = unsafe_wrap(Array, convert(Ptr{UInt32}, unsafe_load(surface).pixels), (width, width))

    srf_fmt = unsafe_load(surface).format

    for y in 1:width
        for x in 1:width
            colour = f(x,y,args...)
            pixels[y, x] = SDL_MapRGBA(srf_fmt, colour.r, colour.g, colour.b, colour.a) 
        end
    end

    SDL_UnlockSurface(surface)
    return texture!(surface,renderer)
end

"return different coloured squares to indicate legal move for brown and cream colours"
function click_sqs(renderer,sq_width,brown,cream)
    blue = [-20, -20, 30, 0] 

    bclk_sq = colour_surface(const_colour,renderer,sq_width,brown.+blue)
    cclk_sq = colour_surface(const_colour,renderer,sq_width,cream.+blue)
    return bclk_sq,cclk_sq
end
   
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

"Takes in a position and places pieces based on ptrs to piece textures"
function render_pieces(renderer,piece_width,position,tex_vec)
    for (i,p) in enumerate(position)
        if p!=0
            x,y = pixel_coords(i-1,piece_width)
            dest_ref = Ref(SDL_Rect(x, y, piece_width, piece_width))
            SDL_RenderCopy(renderer, tex_vec[p], C_NULL, dest_ref)
        end
    end
end

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

function promote_move!(logicstate,index,legal_moves,BOT)
    promotype = [PROMQUEEN,PROMROOK,PROMBISHOP,PROMKNIGHT]

    moveID = findfirst(i->flag(i)==promotype[index],legal_moves)
    GUImove!(legal_moves[moveID],logicstate,BOT)
end

"If pawn is promoting, highlight possible promotions to display on GUI"
function promote_squares(prompos,Whitemove,position)
    inc = ifelse(Whitemove==0,8,-8)
    highlight = []
    Ptype = [val(Queen()),val(Rook()),val(Bishop()),val(Knight())]
    for i in 0:3
        pos = prompos+i*inc
        push!(highlight,pos)
        position[pos+1] = Ptype[i+1]+Whitemove*val(Black())
    end
    return highlight,position
end

"update logic with move made and return true if trying to promote"
function move_clicked!(logicstate,move_from,mouse_pos,kingpos,legal_moves,BOT)
    for move in legal_moves
        if (to(move) == mouse_pos) & (from(move) == move_from)
            if (flag(move) == PROMQUEEN)|(flag(move) == PROMROOK)|(flag(move) == PROMBISHOP)|(flag(move) == PROMKNIGHT)
                return true
            else
                GUImove!(move,logicstate,BOT)
                return false
            end
        #check for castling moves
        elseif move_from == kingpos
            if (mouse_pos == move_from + 2) & (flag(move) == KCASTLE)
                GUImove!(move,logicstate,BOT)
                return false
            elseif (mouse_pos == move_from - 2) & (flag(move) == QCASTLE)
                GUImove!(move,logicstate,BOT)
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
function GUImove!(move,board,vsBOT)
    make_move!(move,board)
    moves = generate_moves(board)
    if vsBOT && !check_win(board)
        #botmove = bot.best_move(board,moves,UInt8(4),true) #test bot version?

        botmove = bot.best_move(board,0.1,true)
        make_move!(botmove,board)
    end
end

"display pieces and chessboard on screen. enable clicking to show and make legal moves"
function main_loop(win,renderer,tex_vec,board,click_sqs,WIDTH,square_width,FEN,vsBOT=false)
    logicstate = Boardstate(FEN)
    position = GUIposition(logicstate)
    legal_moves = generate_moves(logicstate)
    highlight_moves = []    #visualise legal moves for selected piece
    sq_clicked = -1         #position of mouse click in board coords
    promoting = false
    UNMAKE = true           #allow unmaking moves
    try
        close = false
        while !close
            event_ref = Ref{SDL_Event}()
            while Bool(SDL_PollEvent(event_ref))
                evt = event_ref[]
                evt_ty = evt.type
                if evt_ty == SDL_QUIT
                    close = true
                    break 
                elseif UNMAKE & (evt_ty == SDL_KEYUP)
                    #step backwards in move history
                    unmake_move!(logicstate)
                    if vsBOT #need to undo bots turn as well
                       unmake_move!(logicstate) 
                    end

                    #update positions of pieces in GUI representation
                    position = GUIposition(logicstate)
                    #generate new set of moves
                    legal_moves = generate_moves(logicstate)
                    #reset square clicked on to nothing
                    highlight_moves = []
                    sq_clicked = -1
                    
                elseif evt_ty == SDL_MOUSEBUTTONUP
                    mouse_evt = getproperty(evt,:button)
                    xpos = getproperty(mouse_evt,:x)
                    ypos = getproperty(mouse_evt,:y)
                    mouse_pos = board_coords(xpos,ypos,square_width)
                    kingpos = trailing_zeros(ally_pieces(logicstate)[val(King())])

                    if (length(highlight_moves) > 0)
                        if mouse_pos in highlight_moves
                            if promoting
                                index = findfirst(i->i==mouse_pos,highlight_moves)
                                promote_move!(logicstate,index,legal_moves,vsBOT)
                                promoting = false
                            else
                                #make move in logic then update GUI to reflect new board
                                promoting = move_clicked!(logicstate,sq_clicked,mouse_pos,kingpos,legal_moves,vsBOT)
                            end

                            if promoting
                                highlight_moves,position = promote_squares(mouse_pos,logic.ColID(logicstate.Colour),position)
                            else
                                #update positions of pieces in GUI representation
                                position = GUIposition(logicstate)
                                #generate new set of moves
                                legal_moves = generate_moves(logicstate)
                                highlight_moves = []
                            end
                        else
                            #reset square clicked on to nothing
                            highlight_moves = []
                        end
                        sq_clicked = -1
                    else
                        highlight_moves = mouse_clicked(mouse_pos,legal_moves,kingpos)
                        sq_clicked = mouse_pos
                    end
                    check_win(logicstate)
                end
            end

            SDL_RenderClear(renderer)
            SDL_RenderCopy(renderer, board, C_NULL, Ref(SDL_Rect(0,0,WIDTH,WIDTH)))

            if length(highlight_moves) > 0
                for pos in highlight_moves
                    x,y = pixel_coords(pos,square_width)
                    click_sq = click_sqs[2]
                    if is_dark_sq(x+1,y+1,square_width)
                        click_sq = click_sqs[1]
                    end
                    SDL_RenderCopy(renderer,click_sq,C_NULL,Ref(SDL_Rect(x,y,square_width,square_width)))
                end
            end

            render_pieces(renderer,square_width,position,tex_vec)

            SDL_RenderPresent(renderer) 

            SDL_Delay(1000 ÷ 60)
        end
    finally
        SDL_DestroyRenderer(renderer)
        SDL_DestroyWindow(win)
        SDL_Quit()
    end
end

function main()
    #SDL_Quit()
    FEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

    WIDTH = 800
    sq_width = Int(WIDTH÷8)
    brown = [125, 62, 62, 255] 
    cream = [255, 253, 208, 255] 
    win, renderer = startup(WIDTH,WIDTH)
    pieces = load_pieces(renderer)
    board = colour_surface(chessboard,renderer,WIDTH,sq_width,brown,cream)
    bclk_sq,cclk_sq = click_sqs(renderer,sq_width,brown,cream)
    main_loop(win,renderer,pieces,board,[bclk_sq,cclk_sq],WIDTH,sq_width,FEN,true)

end
main()