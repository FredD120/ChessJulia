module logic

export GUIposition, setone, setzero, Boardstate, white_pieces, black_pieces, all_pieces,
Move_BB, piece_iterator, white_iterator, black_iterator, get_kingmoves, get_knightmoves,
determine_piece, identify_locations, current_player_info, generate_moves, Move

setone(num::UInt64,index::Integer) = num | (UInt64(1) << index)

setzero(num::UInt64,index::Integer) = num = num & (~UInt64(1) << index)

mutable struct Boardstate
    WKing::UInt64
    WQueen::UInt64
    WPawn::UInt64
    WBishop::UInt64
    WKnight::UInt64
    WRook::UInt64
    BKing::UInt64
    BQueen::UInt64
    BPawn::UInt64
    BBishop::UInt64
    BKnight::UInt64
    BRook::UInt64
    Castling::UInt64
    EnPassant::UInt64
    Halfmoves::UInt32
    Whitesmove::Bool
end

#Initialise a boardstate from a FEN string
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
        end
        #Positions of  pieces
        if num_spaces == 0
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
            Halfmoves = Int(c)
        end
    end

    Boardstate(WKing,WQueen,WPawn,WBishop,WKnight,WRook,
    BKing,BQueen,BPawn,BBishop,BKnight,BRook,
    Castling,EnPassant,Halfmoves,Whitesmove)
end

function white_pieces(b::Boardstate)
    return b.WKing | b.WQueen | b.WPawn | b.WBishop | b.WKnight | b.WRook
end

function black_pieces(b::Boardstate)
    return b.BKing | b.BQueen | b.BPawn | b.BBishop | b.BKnight | b.BRook
end

all_pieces(b::Boardstate) = white_pieces(b) | black_pieces(b)


piece_iterator(b::Boardstate) = [b.WKing,b.WQueen,b.WPawn,b.WBishop,b.WKnight,b.WRook,
                                 b.BKing,b.BQueen,b.BPawn,b.BBishop,b.BKnight,b.BRook]

white_iterator(b::Boardstate) = [b.WKing,b.WQueen,b.WPawn,b.WBishop,b.WKnight,b.WRook]

black_iterator(b::Boardstate) = [b.BKing,b.BQueen,b.BPawn,b.BBishop,b.BKnight,b.BRook]

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

function read_moves(piece_name)
    moves = Vector{UInt64}(undef,64)
    movelist = readlines("$(pwd())/logic/move_BBs/$(piece_name).txt")
    for (i,m) in enumerate(movelist)
        moves[i] = parse(UInt64,m)
    end   
    return moves
end

struct Move_BB
    king::Vector{UInt64}
    knight::Vector{UInt64}
end

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

function identify_locations(pieceBB::UInt64)::Vector{UInt8}
    locations = Vector{UInt8}()
    for i in UInt8(0):UInt8(63)
        if pieceBB & UInt64(1) << i > 0
            push!(locations,i)
        end
    end
    return locations
end

function moves_from_location(destinations::UInt64,origin::Integer,attackflag::Bool)::Vector{Move}
    locs = identify_locations(destinations)
    moves = Vector{Move}(undef, length(locs))
    for (i,loc) in enumerate(locs)
        moves[i] = Move(origin,loc,attackflag)
    end
    return moves
end

function get_kingmoves(location::UInt8,moveset::Move_BB,enemy_pcs::UInt64,all_pcs::UInt64)::Vector{Move}
    poss_moves = moveset.king[location]
    attacks = poss_moves & enemy_pcs
    quiets = poss_moves ^ all_pcs
    return [moves_from_location(attacks,location,true);moves_from_location(quiets,location,false)]
end

function get_knightmoves(location::UInt8,moveset::Move_BB,enemy_pcs::UInt64,all_pcs::UInt64)::Vector{Move}
    poss_moves = moveset.knight[location]
    attacks = poss_moves & enemy_pcs
    quiets = poss_moves ^ all_pcs
    return [moves_from_location(attacks,location,true);moves_from_location(quiets,location,false)]
end

function determine_piece(pieceID)
    if pieceID == 1
        return get_kingmoves
    elseif pieceID == 5
        return get_knightmoves
    end
end

function current_player_info(board::Boardstate)
    iterator = Vector{UInt64}(undef, 6)
    enemy_pieces = UInt64(0)

    if board.Whitesmove
        iterator = white_iterator(board)
        enemy_pieces = black_pieces(board)
    else
        iterator = black_iterator(board)
        enemy_pieces = white_pieces(board)
    end
    return iterator,enemy_pieces,all_pieces(board)
end

function generate_moves(board::Boardstate,moveset::Move_BB)::Vector{Move}
    iterator,enemy_pcs,all_pcs = current_player_info(board)

    movelist = Vector{Move}()
    for (pieceID,pieceBB) in enumerate(iterator)
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

end
