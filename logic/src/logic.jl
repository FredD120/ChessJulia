module logic

export GUIposition, Boardstate, make_move!, unmake_move!, UCImove,
Neutral, Loss, Draw, generate_moves, Move, Whitesmove, perft

using Random
rng = Xoshiro(2955)

const White = UInt8(0)
const Black = UInt8(6)
const NULL_PIECE = UInt8(0)
const King = UInt8(1)
const Queen = UInt8(2)
const Rook = UInt8(3)
const Bishop = UInt8(4)
const Knight = UInt8(5)
const Pawn = UInt8(6)

const ZobristKeys = rand(rng,UInt64,12*64)

struct Move
    piece_type::UInt8
    from::UInt32
    to::UInt32
    capture_type::UInt8
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

const moveset = Move_BB()

setone(num::UInt64,index::Integer) = num | (UInt64(1) << index)

setzero(num::UInt64,index::Integer) = num & ~(UInt64(1) << index)

struct Neutral end
struct Loss end
struct Draw end

const GameState = Union{Neutral,Loss,Draw}

mutable struct BoardData
    Halfmoves::Vector{UInt8}
    Castling::Vector{UInt64}
    CastleCount::Vector{UInt8}
    EnPassant::Vector{UInt64}
    EPCount::Vector{UInt8}
    ZHashHist::Vector{UInt64}
end

mutable struct Boardstate
    pieces::Vector{UInt64}
    ColourIndex::UInt8
    State::GameState
    ZHash::UInt64
    MoveHist::Vector{Move}
    Data::BoardData
end

"Helper function to determine whose move it is"
Whitesmove(ColourIndex::UInt8) = ColourIndex == 0 ? true : false

"Helper function to return opposite colour index"
Opposite(ColourIndex) = (ColourIndex+6)%12

"returns a list of numbers between 0 and 63 to indicate positions on a chessboard"
function identify_locations(pieceBB::UInt64)::Vector{UInt8}
    locations = Vector{UInt8}()
    temp_BB = pieceBB
    while temp_BB != 0
        loc = trailing_zeros(temp_BB) #find 0-indexed location of least significant bit in BB
        push!(locations,loc)
        temp_BB &= temp_BB - 1        #trick to remove least significant bit
    end
    return locations
end

"loop through a list of piece BBs for one colour and return ID of enemy piece at a location"
function identify_piecetype(one_side_BBs::Vector{UInt64},location::Integer)::UInt8
    ID = NULL_PIECE
    for (pieceID,pieceBB) in enumerate(one_side_BBs)
        if pieceBB & (UInt64(1) << location) != 0
            ID = pieceID
            break
        end
    end
    return ID
end

"Helper function when constructing a boardstate"
function place_piece!(pieces::Vector{UInt64},pieceID,pos)
    pieces[pieceID] = setone(pieces[pieceID],pos)
end

"generate Zobrist hash of a boardstate"
function generate_hash(pieces,Whitesmove,castling,enpassant)
    ZHash = UInt64(0)
    for (pieceID,pieceBB) in enumerate(pieces)
        for loc in identify_locations(pieceBB)
            ZHash ⊻= ZobristKeys[12*(pieceID-1)+loc+1]
        end
    end

    #the rest of this data is packed in using the fact that neither
    #black or white pawns will exist on first or last rank
    for EP in identify_locations(enpassant)
        file = EP % 8
        #use first rank of black pawns
        ZHash ⊻= ZobristKeys[12*(11)+file+1]
    end

    #use last rank of black pawns (not very elegant)
    for C in identify_locations(castling)
        if C == 2
            ZHash ⊻= ZobristKeys[end - 1]
        elseif C == 6
            ZHash ⊻= ZobristKeys[end - 2]
        elseif C == 58
            ZHash ⊻= ZobristKeys[end - 3]
        elseif C == 62
            ZHash ⊻= ZobristKeys[end - 4]
        end
    end

    if !Whitesmove
        ZHash ⊻= ZobristKeys[end]
    end
    return ZHash
end

"Initialise a boardstate from a FEN string"
function Boardstate(FEN)
    pieces = zeros(UInt64,12)
    Castling = UInt64(0)
    EnPassant = UInt64(0)
    Halfmoves = UInt8(0)
    ColourIndex = UInt8(0)
    MoveHistory = Vector{Move}()
    rank = nothing
    file = nothing
    FENdict = Dict('K'=>King,'Q'=>Queen,'R'=>Rook,'B'=>Bishop,'N'=>Knight,'P'=>Pawn)

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
            if isletter(c)
                upperC = uppercase(c)
                if c == upperC
                    colour = White
                else
                    colour = Black
                end
                place_piece!(pieces,FENdict[upperC]+colour,i)
                i+=1
            elseif isnumeric(c)
                i+=parse(Int,c)
            end
        #Determine whose turn it is
        elseif num_spaces == 1
            if c == 'w'
                ColourIndex = White
            elseif c == 'b'
                ColourIndex = Black
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
            Halfmoves = parse(UInt8,c)
        end
    end

    Zobrist = generate_hash(pieces,Whitesmove(ColourIndex),Castling,EnPassant)
    data = BoardData(Vector{UInt8}([Halfmoves]),
                     Vector{UInt64}([Castling]),Vector{UInt8}([0]),
                     Vector{UInt64}([EnPassant]),Vector{UInt8}([0]),
                     Vector{UInt64}([Zobrist]))

    Boardstate(pieces,ColourIndex,Neutral(),Zobrist,MoveHistory,data)
end

"convert a position from number 0-63 to rank/file notation"
function UCIpos(pos)
    file = pos % 8
    rank = 8 - (pos - file)/8 
    return ('a'+file)*string(Int(rank))
end

"convert a move to UCI notation"
function UCImove(move::Move)
    from = UCIpos(move.from)
    to = UCIpos(move.to)
    return from*to
end

"Returns a single bitboard representing the positions of an array of pieces"
function player_pieces(piece_vec::VecOrMat{UInt64})
    BB = UInt64(0)
    for piece in piece_vec
        BB |= piece
    end
    return BB
end

"Helper function to obtain vector of ally bitboards"
ally_pieces(b::Boardstate) = b.pieces[b.ColourIndex+1:b.ColourIndex+6]

"Helper function to obtain vector of enemy bitboards"
function enemy_pieces(b::Boardstate) 
    enemy_ind = Opposite(b.ColourIndex)
    return b.pieces[enemy_ind+1:enemy_ind+6]
end

"tells GUI where pieces are on the board"
function GUIposition(board::Boardstate)
    position = zeros(UInt8,64)
    for (pieceID,piece) in enumerate(board.pieces)
        for i in UInt64(0):UInt64(63)
            if piece & UInt64(1) << i > 0
                position[i+1] = pieceID
            end
        end
    end
    return position
end

"checks enemy pieces to see if any are attacking the current square, returns BB of attackers"
function attackable(board::Boardstate,position::Integer)::UInt64
    attacks = UInt64(0)

    kingmoves = moveset.king[position+1]
    attacks |= (kingmoves & enemy_pieces(board)[1])

    knightmoves = moveset.knight[position+1]
    attacks |= (knightmoves & enemy_pieces(board)[5])

    return attacks
end

"returns true if move is legal, based on whether king is in check, castling is allowed, discovered checks etc"
function is_legal(board::Boardstate,type::UInt8,position::Integer,checks::UInt64)::Bool
    #king moves
    if type == 1
        if attackable(board,position) > 0
            return false
        end
    #if we can capture the sole checking piece it is legal
    elseif setzero(checks,position) > 0
        return false
    end
    return true
end

"creates a move from a given location using the Move struct, with flag for attacks"
function moves_from_location(type::UInt8,board::Boardstate,destinations::UInt64,origin::Integer,checks::UInt64,isattack::Bool)::Vector{Move}
    locs = identify_locations(destinations)
    moves = Vector{Move}()
    for loc in locs
        if is_legal(board,type,loc,checks)
            attacked_pieceID = NULL_PIECE
            if isattack
                #move struct needs info on piece being attacked
                attacked_pieceID = identify_piecetype(enemy_pieces(board),loc)
            end
            push!(moves,Move(type,origin,loc,attacked_pieceID))
        end
    end
    return moves
end

"not yet implemented"
function get_bishopmoves(location::UInt8,board::Boardstate,enemy_pcs::UInt64,all_pcs::UInt64,checks::UInt64)::Vector{Move}
    return []
end

"not yet implemented"
function get_rookmoves(location::UInt8,board::Boardstate,enemy_pcs::UInt64,all_pcs::UInt64,checks::UInt64)::Vector{Move}
    return []
end

"returns attacks and quiet moves by the king"
function get_kingmoves(location::UInt8,board::Boardstate,enemy_pcs::UInt64,all_pcs::UInt64,checks::UInt64)::Vector{Move}
    poss_moves = moveset.king[location+1]
    attacks = poss_moves & enemy_pcs
    quiets = poss_moves & ~all_pcs 
    return [moves_from_location(UInt8(1),board,attacks,location,checks,true);
    moves_from_location(UInt8(1),board,quiets,location,checks,false)]
end

"return both rook and bishop moves"
function get_queenmoves(location::UInt8,board::Boardstate,enemy_pcs::UInt64,all_pcs::UInt64,checks::UInt64)::Vector{Move}
    return [get_rookmoves(location,board,enemy_pcs,all_pcs,checks);
    get_bishopmoves(location,board,enemy_pcs,all_pcs,checks)]
end

"returns attacks and quiet moves by a knight"
function get_knightmoves(location::UInt8,board::Boardstate,enemy_pcs::UInt64,all_pcs::UInt64,checks::UInt64)::Vector{Move}
    poss_moves = moveset.knight[location+1]
    attacks = poss_moves & enemy_pcs
    quiets = poss_moves & ~all_pcs 
    return [moves_from_location(UInt8(5),board,attacks,location,checks,true);
    moves_from_location(UInt8(5),board,quiets,location,checks,false)]
end

"not yet implemented"
function get_pawnmoves(location::UInt8,board::Boardstate,enemy_pcs::UInt64,all_pcs::UInt64,checks::UInt64)::Vector{Move}
    return []
end

const get_piecemoves = [get_kingmoves,get_queenmoves,get_rookmoves,get_bishopmoves,get_knightmoves,get_pawnmoves]

"get lists of pieces and piece types, find locations of owned pieces and create a movelist of all legal moves"
function generate_moves(board::Boardstate)::Vector{Move}
    movelist = Vector{Move}()
    #implement 50 move rule and 3 position repetition
    if (board.Data.Halfmoves[end] >= 100) | (count(i->(i==board.ZHash),board.Data.ZHashHist) >= 3)
        board.State = Draw()
    else
    enemy_pcs = player_pieces(enemy_pieces(board))
    all_pcs = player_pieces(board.pieces)
    checks = UInt64(0)

    for (pieceID,pieceBB) in enumerate(ally_pieces(board))
        if pieceBB > 0
            loc_list = identify_locations(pieceBB)
            for loc in loc_list
                #king is first piece looked at, need checking attackers for move generation
                if pieceID == King
                    checks = attackable(board,loc)
                end
                #use an array of functions to get moves for different pieces
                movelist = vcat(movelist,get_piecemoves[pieceID](loc,board,enemy_pcs,all_pcs,checks))
            end
        end
    end

    if length(movelist) == 0
        if checks > 0
            board.State = Loss()
        else
            board.State = Draw()
        end
    end
    end
    return movelist
end

"utilises setzero to remove a piece from a position"
function destroy_piece!(B::Boardstate,CpieceID,pos)
    B.pieces[CpieceID] = setzero(B.pieces[CpieceID],pos)
    B.ZHash ⊻= ZobristKeys[12*(CpieceID-1)+pos+1]
end

"utilises setone to create a piece in a position"
function create_piece!(B::Boardstate,CpieceID,pos)
    B.pieces[CpieceID] = setone(B.pieces[CpieceID],pos)
    B.ZHash ⊻= ZobristKeys[12*(CpieceID-1)+pos+1]
end

"utilises create and destroy to move single piece"
function move_piece!(B::Boardstate,CpieceID,from,to)
    destroy_piece!(B,CpieceID,from)
    create_piece!(B,CpieceID,to)
end

"switch to opposite colour and update hash key"
function swap_player!(board)
    board.ColourIndex = Opposite(board.ColourIndex)
    board.ZHash ⊻= ZobristKeys[end]
end

"modify boardstate by making a move. increment halfmove count. add move to MoveHist"
function make_move!(move::Move,board::Boardstate)
    move_piece!(board,board.ColourIndex+move.piece_type,move.from,move.to)

    if move.capture_type > 0
        destroy_piece!(board,Opposite(board.ColourIndex)+move.capture_type,move.to)
        push!(board.Data.Halfmoves,0)
    else
        board.Data.Halfmoves[end] += 1
    end
    swap_player!(board)
    push!(board.MoveHist,move)
    push!(board.Data.ZHashHist,board.ZHash)
end

"unmakes last move on MoveHist stack. currently doesn't restore halfmoves"
function unmake_move!(board::Boardstate)
    if length(board.MoveHist) > 0
        move = board.MoveHist[end]
        move_piece!(board,Opposite(board.ColourIndex)+move.piece_type,move.to,move.from)

        if move.capture_type > 0
            create_piece!(board,board.ColourIndex+move.capture_type,move.to)
        end

        if board.Data.Halfmoves[end] > 0 
            board.Data.Halfmoves[end] -= 1
        else
            pop!(board.Data.Halfmoves)
        end

        swap_player!(board)
        pop!(board.MoveHist)
        pop!(board.Data.ZHashHist)
    else
        println("Failed to unmake move: No move history")
    end
end

function perft(board::Boardstate,depth,verbose=false)
    leaf_nodes = 0
    moves = generate_moves(board)

    if depth == 1
        return length(moves)
    else
        for move in moves
            make_move!(move,board)
            nodecount = perft(board,depth-1)
            if verbose == true
             println(UCImove(move) * ": " * string(nodecount))
            end
            leaf_nodes += nodecount
            unmake_move!(board)
        end
    end
    return leaf_nodes
end
end
