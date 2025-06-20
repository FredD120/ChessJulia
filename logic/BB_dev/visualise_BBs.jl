using logic
using SimpleDirectMediaLayer
using SimpleDirectMediaLayer.LibSDL2

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

"update gui based on mouse click to indicate legal moves"
function mouse_clicked!(mouse_pos,highlight_pieces,GUIboard,PLACE_PIECES)
    if PLACE_PIECES
        if count(i->(i==mouse_pos),highlight_pieces) == 0
            push!(highlight_pieces,mouse_pos)
        else
            remove!(highlight_pieces,mouse_pos)
        end
    else
        ## Display pawn moves using bitshifting
        pawns = array_to_BB(highlight_pieces) 
        rshift_mask = UInt64(0xFEFEFEFEFEFEFEFE)
        lshift_mask = UInt64(0x7F7F7F7F7F7F7F7F)

        pawn_push = pawns << 8
        pawn_left = (pawn_push >> 1) & lshift_mask
        pawn_right = (pawn_push << 1) & rshift_mask

        GUIboard .= [0x09, 0x00, 0x00, 0x08, 0x07, 0x00, 0x00, 0x09, 0x0c, 0x00, 0x0c, 0x0c, 0x00, 0x02, 0x0a, 0x00, 0x0a, 0x0b, 0x00, 0x00, 0x0c, 0x00, 0x0c, 0x00, 0x00, 0x00, 0x00, 0x06, 0x05, 0x00, 0x00, 0x00, 0x00, 0x0c, 0x00, 0x00, 0x06, 0x00, 0x00, 0x00, 0x00, 0x00, 0x05, 0x00, 0x00, 0x00, 0x00, 0x0c, 0x06, 0x06, 0x06, 0x04, 0x04, 0x06, 0x06, 0x06, 0x03, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x03] #GUIboard .= set_GUI(GUIboard,pawn_push,val(Pawn()))
        #GUIboard .= set_GUI(GUIboard,pawn_left,val(Bishop()))
        #GUIboard .= set_GUI(GUIboard,pawn_right,val(Rook()))

         #Display rook and bishop moves using magic BBs 
        #blockers = array_to_BB(highlight_pieces) 
        #move_BB = logic.sliding_attacks(logic.BishopMagics[mouse_pos+1],blockers)

        #GUIboard .= get_GUI_moves(514,val(logic.Bishop()))
        
    end
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

"display pieces and chessboard on screen. enable clicking to show and make legal moves"
function main_loop(win,renderer,board,pieces,click_sqs,WIDTH,square_width)
    highlight_pieces = []   #visualise pseudo-pieces
    GUIboard = zeros(Integer,64)    #visualise rook moves
    MODE = true
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
                elseif evt_ty == SDL_KEYUP
                    MODE = !MODE
                    GUIboard = zeros(Integer,64)
                elseif evt_ty == SDL_MOUSEBUTTONUP
                    mouse_evt = getproperty(evt,:button)
                    xpos = getproperty(mouse_evt,:x)
                    ypos = getproperty(mouse_evt,:y)
                    mouse_pos = board_coords(xpos,ypos,square_width)

                    mouse_clicked!(mouse_pos,highlight_pieces,GUIboard,MODE)
                end
            end

            SDL_RenderClear(renderer)
            SDL_RenderCopy(renderer, board, C_NULL, Ref(SDL_Rect(0,0,WIDTH,WIDTH)))

            for pos in highlight_pieces
                x,y = pixel_coords(pos,square_width)
                SDL_RenderCopy(renderer,click_sqs[1],C_NULL,Ref(SDL_Rect(x,y,square_width,square_width)))
            end
            render_pieces(renderer,square_width,GUIboard,pieces)

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
    WIDTH = 800
    sq_width = Int(WIDTH÷8)
    brown = [125, 62, 62, 255] 
    cream = [255, 253, 208, 255] 
    win, renderer = startup(WIDTH,WIDTH)
    pieces = load_pieces(renderer)
    board = colour_surface(chessboard,renderer,WIDTH,sq_width,brown,cream)
    bclk_sq,cclk_sq = click_sqs(renderer,sq_width,brown,cream)
    main_loop(win,renderer,board,pieces,[bclk_sq,cclk_sq],WIDTH,sq_width)

end
main()

