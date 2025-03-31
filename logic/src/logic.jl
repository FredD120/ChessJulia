module logic

using BenchmarkTools

export GUIposition, setone, setzero, Boardstate, white_pieces, black_pieces, Moves

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

function piece_iterator(b::Boardstate)
    return [b.WKing,b.WQueen,b.WPawn,b.WBishop,b.WKnight,b.WRook,
    b.BKing,b.BQueen,b.BPawn,b.BBishop,b.BKnight,b.BRook]
end

function with_pieces(f,board,args...)
    for (e,piece) in enumerate(piece_iterator(board))
        f(e,piece,args...)
    end
end


struct Moves
    knight::Vector{UInt64}
end

function Moves()
    knight_moves = Vector{UInt64}(undef,64)
    movelist = readlines("$(pwd())/logic/move_BBs/knight.txt")
    for (i,m) in enumerate(movelist)
        knight_moves[i] = parse(UInt64,m)
    end   
    return Moves(knight_moves)
end

function GUIposition(board::Boardstate)
    position = zeros(UInt8,64)
    with_pieces(board,position) do e,piece,position
        for i in 0:63
            if piece & UInt64(1) << i > 0
                position[i+1] = e
            end
        end
    end
    return position
end

end
