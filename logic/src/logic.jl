module logic

export GUIposition, setone, setzero, Boardstate, player_pieces, all_pieces,
Move_BB, piece_iterator, get_kingmoves, get_knightmoves, make_move!,
determine_piece, identify_locations, moves_from_location, generate_moves, Move

setone(num::UInt64,index::Integer) = num | (UInt64(1) << index)

setzero(num::UInt64,index::Integer) = num & ~(UInt64(1) << index)

mutable struct Boardstate
    ally_pieces::Vector{UInt64}
    enemy_pieces::Vector{UInt64}
    Castling::UInt64
    EnPassant::UInt64
    Halfmoves::UInt32
    Whitesmove::Bool
end

"Initialise a boardstate from a FEN string"
function Boardstate(FEN)
    WKing = UInt64(0)
    WQueen = UInt64(0)
    WPawn = UInt64(0)
    WBishop = UInt64(0)
    WKnight = UInt64(0)
    WRook = UInt64(0)
    BKing = UInt64(0)
    BQueen = UInt64(0)
    BPawn = UInt64(0)
    BBishop = UInt64(0)
    BKnight = UInt64(0)
    BRook = UInt64(0)
    Castling = UInt64(0)
    EnPassant = UInt64(0)
    Halfmoves = UInt32(0)
    Whitesmove = Bool(true)
    rank = nothing
    file = nothing

    #Keep track of where we are on chessboard
    i = UInt32(0)         
    #Sections of FEN string are separated by ' '      
    num_spaces = UInt32(0)      
    for c in FEN
        #use spaces to know where we are in FEN
        if c == ' '
            num_spaces += 1
        #Positions of  pieces
        elseif num_spaces == 0
            if c == 'K'
                WKing = setone(WKing,i)
                i+=1
            elseif c == 'Q'
                WQueen = setone(WQueen,i)
                i+=1
            elseif c == 'P'
                WPawn = setone(WPawn,i)
                i+=1
            elseif c == 'B'
                WBishop = setone(WBishop,i)
                i+=1
            elseif c == 'N'
                WKnight = setone(WKnight,i)
                i+=1
            elseif c == 'R'
                WRook = setone(WRook,i)
                i+=1

            elseif c == 'k'
                BKing = setone(BKing,i)
                i+=1
            elseif c == 'q'
                BQueen = setone(BQueen,i)
                i+=1
            elseif c == 'p'
                BPawn = setone(BPawn,i)
                i+=1
            elseif c == 'b'
                BBishop = setone(BBishop,i)
                i+=1
            elseif c == 'n'
                BKnight = setone(BKnight,i)
                i+=1
            elseif c == 'r'
                BRook = setone(BRook,i)
                i+=1
            
            elseif isnumeric(c)
                i+=parse(Int,c)
            end
        #Determine whose turn it is
        elseif num_spaces == 1
            if c == 'w'
                Whitesmove = true
            elseif c == 'b'
                Whitesmove = false
            end
        #castling rights
        elseif num_spaces == 2
            if c == 'K'
                Castling = setone(Castling,62)
            elseif c == 'Q'
                Castling = setone(Castling,58)
            elseif c == 'k'
                Castling = setone(Castling,6)
            elseif c == 'q'
                Castling = setone(Castling,2)
            end
        #en-passant
        elseif num_spaces == 3
            if isnumeric(c)
                rank = parse(Int,c)
            elseif c != '-'
                file = Int(c) - Int('a') + 1
            end
            if !isnothing(rank) && !isnothing(file)
                EnPassant = setone(EnPassant,(-rank+8)*8 + file-1)
            end
        elseif num_spaces == 4
            Halfmoves = parse(UInt32,c)
        end
    end

    if Whitesmove
        Boardstate([WKing,WQueen,WPawn,WBishop,WKnight,WRook],
        [BKing,BQueen,BPawn,BBishop,BKnight,BRook],
        Castling,EnPassant,Halfmoves,Whitesmove)
    else
        Boardstate([BKing,BQueen,BPawn,BBishop,BKnight,BRook],
        [WKing,WQueen,WPawn,WBishop,WKnight,WRook],
        Castling,EnPassant,Halfmoves,Whitesmove)
    end
end

function player_pieces(piece_vec::Vector{UInt64})
    BB = UInt64(0)
    for piece in piece_vec
        BB |= piece
    end
    return BB
end

all_pieces(b::Boardstate) = player_pieces(vcat(b.ally_pieces,b.enemy_pieces))

piece_iterator(b::Boardstate) = b.Whitesmove ? vcat(b.ally_pieces,b.enemy_pieces) : vcat(b.enemy_pieces,b.ally_pieces)

"tells GUI where pieces are on the board"
function GUIposition(board::Boardstate)
    position = zeros(UInt8,64)
    for (pieceID,piece) in enumerate(piece_iterator(board))
        for i in UInt64(0):UInt64(63)
            if piece & UInt64(1) << i > 0
                position[i+1] = pieceID
            end
        end
    end
    return position
end

"take in all possible moves for a given piece from a txt file"
function read_moves(piece_name)
    moves = Vector{UInt64}(undef,64)
    movelist = readlines("$(dirname(@__DIR__))/move_BBs/$(piece_name).txt")
    for (i,m) in enumerate(movelist)
        moves[i] = parse(UInt64,m)
    end   
    return moves
end

struct Move_BB
    king::Vector{UInt64}
    knight::Vector{UInt64}
end

"constructor for Move_BB that reads all moves from txt files"
function Move_BB()
    king_mvs = read_moves("king")
    knight_mvs = read_moves("knight")
    return Move_BB(king_mvs,knight_mvs)
end

struct Move
    from::UInt32
    to::UInt32
    iscapture::Bool
end

"returns a number between 0 and 63 to indicate where we are on a chessboard"
function identify_locations(pieceBB::UInt64)::Vector{UInt8}
    locations = Vector{UInt8}()
    for i in UInt8(0):UInt8(63)
        if pieceBB & UInt64(1) << i > 0
            push!(locations,i)
        end
    end
    return locations
end

"creates a move from a given location using the Move struct, with flag for attacks"
function moves_from_location(destinations::UInt64,origin::Integer,attackflag::Bool)::Vector{Move}
    locs = identify_locations(destinations)
    moves = Vector{Move}(undef, length(locs))
    for (i,loc) in enumerate(locs)
        moves[i] = Move(origin,loc,attackflag)
    end
    return moves
end

"returns attacks and quiet moves by the king"
function get_kingmoves(location::UInt8,moveset::Move_BB,enemy_pcs::UInt64,all_pcs::UInt64)::Vector{Move}
    poss_moves = moveset.king[location+1]
    attacks = poss_moves & enemy_pcs
    quiets = poss_moves & ~all_pcs 
    return [moves_from_location(attacks,location,true);moves_from_location(quiets,location,false)]
end

"returns attacks and quiet moves by a knight"
function get_knightmoves(location::UInt8,moveset::Move_BB,enemy_pcs::UInt64,all_pcs::UInt64)::Vector{Move}
    poss_moves = moveset.knight[location+1]
    attacks = poss_moves & enemy_pcs
    quiets = poss_moves & ~all_pcs 
    return [moves_from_location(attacks,location,true);moves_from_location(quiets,location,false)]
end

"uses integer ID to determine type of piece (returns a function)"
function determine_piece(pieceID::Integer)
    if pieceID == 1
        return get_kingmoves
    elseif pieceID == 5
        return get_knightmoves
    end
end

"get lists of pieces and piece types, find locations of owned pieces and create a movelist of all legal moves"
function generate_moves(board::Boardstate,moveset::Move_BB)::Vector{Move}
    enemy_pcs = player_pieces(board.enemy_pieces)
    all_pcs = all_pieces(board)

    movelist = Vector{Move}()
    for (pieceID,pieceBB) in enumerate(board.ally_pieces)
        if pieceBB > 0
            piece_locations = identify_locations(pieceBB)
            get_moves = determine_piece(pieceID)

            for loc in piece_locations
                #compiler might not like not knowing what function get_moves is ahead of time
                #especially if the different functions have different numbers of methods
                movelist = vcat(movelist,get_moves(loc,moveset,enemy_pcs,all_pcs))
            end
        end
    end
    return movelist
end

"modify boardstate by making a move"
function make_move!(move::Move,board::Boardstate,piecetype::Integer)
    #need to swap ally and enemy as well as deleting and replacing pieces
    enemy_copy = copy(board.enemy_pieces)

    for (i,ally) in enumerate(board.ally_pieces)
        if i == piecetype
            ally = setone(ally,move.to)
        end
        board.enemy_pieces[i] = setzero(ally,move.from)
    end

    for (i,enemy) in enumerate(enemy_copy)
        board.ally_pieces[i] = setzero(enemy,move.to)
    end

    board.Halfmoves += 1
    board.Whitesmove = !board.Whitesmove
end

end
