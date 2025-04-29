using logic
using JLD2
using SimpleDirectMediaLayer
using SimpleDirectMediaLayer.LibSDL2

function get_rook_dict()
    path = "$(pwd())/logic/move_BBs/RookMoves/"
    filename = "Rook_dicts.jld2"
    movedict = Vector{Dict{UInt64,UInt64}}()
    jldopen(path*filename, "r") do file
        movedict = file["filename"]
    end

    masks = Vector{UInt64}()
    masks = logic.read_moves("RookMasks")
    return movedict,masks
end

rook_lookup,rook_mask = get_rook_dict()

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

    texture_vec[logic.King+logic.White] = get_texture(renderer,filepath,"WhiteKing")
    texture_vec[logic.Queen+logic.White] = get_texture(renderer,filepath,"WhiteQueen")
    texture_vec[logic.Pawn+logic.White] = get_texture(renderer,filepath,"WhitePawn")
    texture_vec[logic.Bishop+logic.White] = get_texture(renderer,filepath,"WhiteBishop")
    texture_vec[logic.Knight+logic.White] = get_texture(renderer,filepath,"WhiteKnight")
    texture_vec[logic.Rook+logic.White] = get_texture(renderer,filepath,"WhiteRook")
    texture_vec[logic.King+logic.Black] = get_texture(renderer,filepath,"BlackKing")
    texture_vec[logic.Queen+logic.Black] = get_texture(renderer,filepath,"BlackQueen")
    texture_vec[logic.Pawn+logic.Black] = get_texture(renderer,filepath,"BlackPawn")
    texture_vec[logic.Bishop+logic.Black] = get_texture(renderer,filepath,"BlackBishop")
    texture_vec[logic.Knight+logic.Black] = get_texture(renderer,filepath,"BlackKnight")
    texture_vec[logic.Rook+logic.Black] = get_texture(renderer,filepath,"BlackRook")

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

"lookup rook moves in dict"
function rook_moves(board_sq,all_pieces)
    blocker_BB = all_pieces & rook_mask[board_sq+1]
    return rook_lookup[board_sq+1][blocker_BB]
end

"convert a bitboard to visualise in GUI"
function get_GUI_moves(BB)
    pos_list = logic.identify_locations(BB)
    GUIboard = zeros(Integer,64)
    for pos in pos_list
        GUIboard[pos+1] = logic.Rook
    end
    return GUIboard
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
        blockers = array_to_BB(highlight_pieces) 
        move_BB = rook_moves(mouse_pos,blockers) #needs to belong to logic
        GUIboard .= get_GUI_moves(move_BB)
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