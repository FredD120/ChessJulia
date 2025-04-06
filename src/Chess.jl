using SimpleDirectMediaLayer
using SimpleDirectMediaLayer.LibSDL2
using logic
#using libpng_jll

function startup(WIDTH=1000,HEIGHT=1000)
    SDL_GL_SetAttribute(SDL_GL_MULTISAMPLEBUFFERS, 16)
    SDL_GL_SetAttribute(SDL_GL_MULTISAMPLESAMPLES, 16)

    @assert SDL_Init(SDL_INIT_EVERYTHING) == 0 "error initializing SDL: $(unsafe_string(SDL_GetError()))"

    win = SDL_CreateWindow("Game", SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED, WIDTH, HEIGHT, SDL_WINDOW_SHOWN)
    SDL_SetWindowResizable(win, SDL_TRUE)

    renderer = SDL_CreateRenderer(win, -1, SDL_RENDERER_ACCELERATED | SDL_RENDERER_PRESENTVSYNC)
    return win,renderer
end

function texture!(surface,renderer)
    # Create texture from surface and delete surface
    tex = SDL_CreateTextureFromSurface(renderer, surface)
    if tex == C_NULL
        error("Failed to create texture")
    end

    SDL_FreeSurface(surface)
    return tex
end

function get_texture(renderer,path,name)
    #retrieve texture from file
    surface = IMG_Load("$(path)$(name).png")
    @assert surface != C_NULL "Error loading image: $(unsafe_string(SDL_GetError()))"

    return texture!(surface,renderer)
end

function load_pieces(renderer)
    #loads chess pieces from file and creates vector of pointers to textures
    filepath = "$(pwd())/ChessPieces/"
    texture_vec = Vector{Ptr{SDL_Texture}}(undef,12)

    texture_vec[1] = get_texture(renderer,filepath,"WhiteKing")
    texture_vec[2] = get_texture(renderer,filepath,"WhiteQueen")
    texture_vec[3] = get_texture(renderer,filepath,"WhitePawn")
    texture_vec[4] = get_texture(renderer,filepath,"WhiteBishop")
    texture_vec[5] = get_texture(renderer,filepath,"WhiteKnight")
    texture_vec[6] = get_texture(renderer,filepath,"WhiteRook")
    texture_vec[7] = get_texture(renderer,filepath,"BlackKing")
    texture_vec[8] = get_texture(renderer,filepath,"BlackQueen")
    texture_vec[9] = get_texture(renderer,filepath,"BlackPawn")
    texture_vec[10] = get_texture(renderer,filepath,"BlackBishop")
    texture_vec[11] = get_texture(renderer,filepath,"BlackKnight")
    texture_vec[12] = get_texture(renderer,filepath,"BlackRook")

    return texture_vec
end

const_colour(x,y,c) = SDL_Color(c[1], c[2], c[3], c[4])

function chessboard(x,y,width)
    square_size = width ÷ 8  # Integer division
    brown = SDL_Color(125, 62, 62, 255)  # Brown
    cream = SDL_Color(255, 253, 208, 255)  # Cream

    # Checkerboard pattern
    if ((x - 1) ÷ square_size + (y - 1) ÷ square_size) % 2 == 0
        return brown
    else
        return cream
    end
end

function colour_surface(f,args,renderer,width,height=width)
    # Create surface (32-bit RGBA format)
    surface = SDL_CreateRGBSurfaceWithFormat(0, width, height, 32, SDL_PIXELFORMAT_RGBA32)
    if surface == C_NULL
        error("Failed to create surface")
    end

    SDL_LockSurface(surface) != 0 && error("Failed to lock surface")

    # Get pixel data as a Ptr{UInt32} (since format is RGBA32)
    pixels = unsafe_wrap(Array, convert(Ptr{UInt32}, unsafe_load(surface).pixels), (width, height))

    srf_fmt = unsafe_load(surface).format

    for y in 1:width
        for x in 1:width
            colour = f(x,y,args)
            pixels[y, x] = SDL_MapRGBA(srf_fmt, colour.r, colour.g, colour.b, colour.a) 
        end
    end

    SDL_UnlockSurface(surface)
    return texture!(surface,renderer)
end
   
function pixel_coords(i,sq_width)
    #take in square pos from 1 to 64 and translate to pixel position of centre of square
    xpos = (i-1) % 8
    ypos = (i - 1 - xpos) / 8
    return xpos*sq_width, ypos*sq_width
end

function board_coords(xpos,ypos,sq_width)
    x = Int((xpos - (xpos % sq_width))/sq_width) + 1
    y = Int((ypos - (ypos % sq_width))/sq_width)
    return x + y*8
end

function render_pieces(renderer,piece_width,position,tex_vec)
    #Takes in a position and places pieces based on ptrs to piece textures
    for (i,p) in enumerate(position)
        if p!=0
            x,y = pixel_coords(i,piece_width)
            dest_ref = Ref(SDL_Rect(x, y, piece_width, piece_width))
            SDL_RenderCopy(renderer, tex_vec[p], C_NULL, dest_ref)
        end
    end
end

function mouse_clicked(mouse_pos,all_moves,DEBUG)
    if DEBUG
        piecemoves = all_moves.knight[mouse_pos]
        return identify_locations(piecemoves)
    else
        if position[mouse_pos] > 0 
            return [mouse_pos]
        else
            return []
        end
    end
end

function main_loop(win,renderer,tex_vec,board,click_sq,WIDTH,FEN,DEBUG=false)
    square_width = Int(WIDTH/8)
    logicstate = logic.Boardstate(FEN)
    position = logic.GUIposition(logicstate)#
    all_moves = Move_BB()
    click_pos = []
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
                elseif evt_ty == SDL_MOUSEBUTTONUP
                    mouse_evt = getproperty(evt,:button)
                    xpos = getproperty(mouse_evt,:x)
                    ypos = getproperty(mouse_evt,:y)
                    mouse_pos = board_coords(xpos,ypos,square_width)

                    click_pos = mouse_clicked(mouse_pos,all_moves,DEBUG)
                    #position = get_position()
                end
            end

            SDL_RenderClear(renderer)
            SDL_RenderCopy(renderer, board, C_NULL, Ref(SDL_Rect(0,0,WIDTH,WIDTH)))

            if length(click_pos) > 0
                for pos in click_pos
                    x,y = pixel_coords(pos,square_width)
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
    #FEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
    #test knights and kings
    #FEN = "nnnnknnn/8/8/8/8/8/8/NNNNKNNN w KQkq - 0 1"
    FEN="8/8/4nK2/8/8/8/8/8 w KQkq - 0 1"
    WIDTH = 800
    win, renderer = startup(WIDTH,WIDTH)
    pieces = load_pieces(renderer)
    board = colour_surface(chessboard,WIDTH,renderer,WIDTH)
    click_sq = colour_surface(const_colour,[205, 253, 158, 255],renderer,Int(WIDTH/8))
    main_loop(win,renderer,pieces,board,click_sq,WIDTH,FEN,true)

end
main()