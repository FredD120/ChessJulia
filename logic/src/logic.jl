module logic

export GUIposition, Boardstate, make_move!, unmake_move!, UCImove,
Neutral, Loss, Draw, generate_moves, Move, Whitesmove, perft,
King, Queen, Rook, Bishop, Knight, Pawn, White, Black, val

using InteractiveUtils
using JLD2
using Random
rng = Xoshiro(2955)

const White = UInt8(0)
const Black = UInt8(6)
const NULL_PIECE = UInt8(0)

struct King end
struct Queen end
struct Rook end
struct Bishop end
struct Knight end
struct Pawn end

const piecetypes = [King(),Queen(),Rook(),Bishop(),Knight(),Pawn()]

"Return index associated with piecetype"
val(::King) = UInt8(1)
val(::Queen) = UInt8(2)
val(::Rook) = UInt8(3)
val(::Bishop) = UInt8(4)
val(::Knight) = UInt8(5)
val(::Pawn) = UInt8(6)

Base.string(::King) = "King"
Base.string(::Queen) = "Queen"
Base.string(::Rook) = "Rook"
Base.string(::Bishop) = "Bishop"
Base.string(::Knight) = "Knight"
Base.string(::Pawn) = "Pawn"

const ZobristKeys = rand(rng,UInt64,12*64)

struct Move
    piece_type::UInt8
    from::UInt32
    to::UInt32
    capture_type::UInt8
end

Base.show(io::IO,m::Move) = print(io,"From=$(Int(m.from));To=$(Int(m.to));PieceId=$(Int(m.piece_type));Capture ID=$(Int(m.capture_type))")

"take in all possible moves for a given piece from a txt file"
function read_txt(filename)
    data = Vector{UInt64}()
    data_str = readlines("$(dirname(@__DIR__))/move_BBs/$(filename).txt")
    for d in data_str
        push!(data, parse(UInt64,d))
    end   
    return data
end

struct Move_BB
    king::Vector{UInt64}
    knight::Vector{UInt64}
end

"constructor for Move_BB that reads all moves from txt files"
function Move_BB()
    king_mvs = read_txt("king")
    knight_mvs = read_txt("knight")
    return Move_BB(king_mvs,knight_mvs)
end

const moveset = Move_BB()

struct Magic 
    MagNum::UInt64
    Mask::UInt64
    BitShift::UInt8
    Attacks::Vector{UInt64}
end

function read_magics(piece)
    path = "$(dirname(@__DIR__))/move_BBs/Magic$(piece)s.jld2"
    Masks = UInt64[]
    Magics = UInt64[]
    BitShifts = UInt8[]
    AttackVec = Vector{UInt64}[]

    jldopen(path, "r") do file
        Masks = file["Masks"]
        Magics = file["Magics"]
        BitShifts = file["BitShifts"]
        AttackVec = file["AttackVec"]
    end

    MagicVec = Magic[]
    for (mask,magic,shift,attacks) in zip(Masks,Magics,BitShifts,AttackVec)
        push!(MagicVec,Magic(magic,mask,shift,attacks))
    end
    return MagicVec
end

const BishopMagics = read_magics("Bishop")
const RookMagics = read_magics("Rook")

"Magic function to transform positional information to an index (0-63) into an attack lookup table"
magicIndex(BB,num,N) = (BB*num) >> (64-N)

"Uses magic bitboards to identify blockers and retrieve legal attacks against them"
function sliding_attacks(MagRef::Magic,all_pieces)
    blocker_BB = all_pieces & MagRef.Mask
    return MagRef.Attacks[magicIndex(blocker_BB,MagRef.MagNum,MagRef.BitShift)+1]
end

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
    FENdict = Dict('K'=>val(King()),'Q'=>val(Queen()),'R'=>val(Rook()),'B'=>val(Bishop()),'N'=>val(Knight()),'P'=>val(Pawn()))

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
function BBunion(piece_vec::VecOrMat{UInt64})
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

"store information about how to make moves without king being captured"
struct LegalInfo
    checks::UInt64
    blocks::UInt64
    attack_sqs::UInt64
    attack_num::UInt8
end

"All pseudolegal King moves"
possible_moves(::King,location,all_pcs) = moveset.king[location+1]
"All pseudolegal Knight moves"
possible_moves(::Knight,location,all_pcs) = moveset.knight[location+1]
"All pseudolegal Rook moves"
possible_moves(::Rook,location,all_pcs) = sliding_attacks(RookMagics[location+1],all_pcs)
"All pseudolegal Bishop moves"
possible_moves(::Bishop,location,all_pcs) = sliding_attacks(BishopMagics[location+1],all_pcs)
"All pseudolegal Queen moves"
possible_moves(::Queen,location,all_pcs) = sliding_attacks(RookMagics[location+1],all_pcs) | sliding_attacks(BishopMagics[location+1],all_pcs)
"Not yet implemented, but must only be attacking moves"
possible_moves(::Pawn,location,all_pcs) = UInt64(0)

"checks enemy pieces to see if any are attacking the king square, returns BB of attackers"
function attack_pcs(pc_list::Vector{UInt64},all_pcs::UInt64,location::Integer)::UInt64
    attacks = UInt64(0)
    knightmoves = possible_moves(Knight(),location,all_pcs)
    attacks |= (knightmoves & pc_list[val(Knight())])

    rookmoves = possible_moves(Rook(),location,all_pcs)
    rookattacks = (rookmoves & (pc_list[val(Rook())] | pc_list[val(Queen())]))
    attacks |= rookattacks

    bishopmoves = possible_moves(Bishop(),location,all_pcs)
    bishopattacks = (bishopmoves & (pc_list[val(Bishop())] | pc_list[val(Queen())]))
    attacks |= bishopattacks

    return attacks
end

"Bitboard of all squares being attacked by a side"
function all_poss_moves(pc_list::Vector{UInt64},all_pcs)
    attacks = UInt64(0)

    for (pieceBB,type) in zip(pc_list,piecetypes)
        for location in identify_locations(pieceBB)
            attacks |= possible_moves(type,location,all_pcs)
        end
    end
    return attacks
end

"detect pins and create rook/bishop pin BBs"
function detect_pins(pos,pc_list,all_pcs,ally_pcs)
    #imagine king is a queen, what can it see?
    slide_attacks = possible_moves(Queen(),pos,all_pcs)
    #identify ally pieces seen by king
    ally_block = slide_attacks & ally_pcs
    #remove these ally pieces
    blocks_removed = all_pcs & ~ally_block

    #recalculate rook attacks with blockers removed
    rook_no_blocks = possible_moves(Rook(),pos,blocks_removed) 
    #only want moves found after removing blockers
    rpin_attacks = rook_no_blocks & ~slide_attacks
    #start by adding attacker to pin line
    rookpins = rpin_attacks & (pc_list[val(Rook())] | pc_list[val(Queen())])
    #iterate through rooks/queens pinning king
    for loc in identify_locations(rookpins)
        #add squares on pin line to pinning BB
        rookpins |= rook_no_blocks & possible_moves(Rook(),loc,blocks_removed)
    end

    #same but for bishops
    bishop_no_blocks = possible_moves(Bishop(),pos,blocks_removed) 
    bpin_attacks = bishop_no_blocks & ~slide_attacks
    bishoppins = bpin_attacks & (pc_list[val(Bishop())] | pc_list[val(Queen())])
    for loc in identify_locations(bishoppins)
        bishoppins |= bishop_no_blocks & possible_moves(Bishop(),loc,blocks_removed)
    end

    return rookpins,bishoppins
end

"returns struct containing info on attacks, blocks and pins of king by enemy piecelist"
function attack_info(pc_list::Vector{UInt64},all_pcs::UInt64,position,KingBB)::LegalInfo
    attacks = typemax(UInt64)
    blocks = UInt64(0)
    attacker_num = 0

    #construct BB of all enemy attacks, must remove king when checking if square is attacked
    all_except_king = all_pcs & ~(KingBB)
    attacked_sqs = all_poss_moves(pc_list,all_except_king)

    #if king not under attack, dont need to find attacking pieces or blockers
    if KingBB & attacked_sqs == UInt64(0) 
        blocks = typemax(UInt64)
    else
        attacks = attack_pcs(pc_list,all_pcs,position)
        attacker_num = count_ones(attacks)
        #if only a single sliding piece is attacking the king, it can be blocked
        if attacker_num == 1
            for piece in [Rook(),Bishop()]
                kingmoves = possible_moves(piece,position,all_pcs)
                slide_attckers = kingmoves & (pc_list[val(piece)] | pc_list[val(Queen())])
                for attack_pos in identify_locations(slide_attckers)
                    attackmoves = possible_moves(piece,attack_pos,all_pcs)
                    blocks |= attackmoves & kingmoves
                end
            end
        end
    end
    
    return LegalInfo(attacks,blocks,attacked_sqs,attacker_num)
end

"creates a move from a given location using the Move struct, with flag for attacks"
function moves_from_location(type::UInt8,enemy_pcs::Vector{UInt64},destinations::UInt64,origin,isattack::Bool)::Vector{Move}
    locs = identify_locations(destinations)
    moves = Vector{Move}()
    for loc in locs
        attacked_pieceID = NULL_PIECE
        if isattack
            #move struct needs info on piece being attacked
            attacked_pieceID = identify_piecetype(enemy_pcs,loc)
        end
        push!(moves,Move(type,origin,loc,attacked_pieceID))
    end
    return moves
end

"Bitboard containing only the attacks by a particular piece"
function attack_moves(moveBB,enemy_pcs)
    return moveBB & enemy_pcs
end

"Bitboard containing only the quiets by a particular piece"
function quiet_moves(moveBB,all_pcs)
    return moveBB & ~all_pcs
end

"Filter possible moves for legality for King"
function legal_moves(piece::King,loc,all_pcs,rookpins,bishoppins,info::LegalInfo)
    poss_moves = possible_moves(piece,loc,all_pcs)
    #Filter out moves that put king in check
    legal_moves = poss_moves & ~info.attack_sqs
    return legal_moves
end

"Filter possible moves for legality for Knight"
function legal_moves(piece::Knight,loc,all_pcs,rookpins,bishoppins,info::LegalInfo)
    poss_moves = possible_moves(piece,loc,all_pcs)
    #Filter out knight moves that don't block/capture if in check/pinned
    legal_moves = poss_moves & (info.checks | info.blocks) 
    return legal_moves
end

"Filter possible moves for legality for Bishop"
function legal_moves(piece::Bishop,loc,all_pcs,rookpins,bishoppins,info::LegalInfo)
    poss_moves = possible_moves(piece,loc,all_pcs)
    #Filter out bishop moves that don't block/capture if in check/pinned
    legal_moves = poss_moves & (info.checks | info.blocks) & bishoppins
    return legal_moves
end

"Filter possible moves for legality for Rook"
function legal_moves(piece::Rook,loc,all_pcs,rookpins,bishoppins,info::LegalInfo)
    poss_moves = possible_moves(piece,loc,all_pcs)
    #Filter out rook moves that don't block/capture if in check/pinned
    legal_moves = poss_moves & (info.checks | info.blocks) & rookpins
    return legal_moves
end

"Filter possible moves for legality for Queen"
function legal_moves(::Queen,loc,all_pcs,rookpins,bishoppins,info::LegalInfo)
    legal_rook = legal_moves(Rook(),loc,all_pcs,rookpins,bishoppins,info)
    legal_bishop = legal_moves(Bishop(),loc,all_pcs,rookpins,bishoppins,info)
    return legal_rook | legal_bishop
end

"Bitboard logic to get attacks and quiets for non-pawns"
function QAtt(piece::Union{King,Knight,Bishop,Rook,Queen},loc,all_pcs,enemy_pcs,rookpins,bishoppins,info::LegalInfo)
    legal = legal_moves(piece,loc,all_pcs,rookpins,bishoppins,info)

    attacks = attack_moves(legal,enemy_pcs)
    quiets = quiet_moves(legal,all_pcs)
    return quiets,attacks
end

"King cannot be pinned, knight cannot move if pinned"
pinned(::Union{King,Knight},pieceBB,rookpins,bishoppins) = UInt64(0)

"Bishop can only move if pinned diagonally"
pinned(::Bishop,pieceBB,rookpins,bishoppins) = pieceBB & bishoppins

"Rook can only move if pinned vertic/horizontally"
pinned(::Rook,pieceBB,rookpins,bishoppins) = pieceBB & rookpins

"Queen may move in any pin"
pinned(::Queen,pieceBB,rookpins,bishoppins) = pieceBB & (rookpins | bishoppins)

"Placeholder"
pinned(::Pawn,pieceBB,rookpins,bishoppins) = UInt64(0)

"returns attack and quiet moves only if legal, based on checks and pins"
function get_moves(piece,pieceBB,enemy_vec::Vector{UInt64},enemy_pcs,all_pcs,rookpins,bishoppins,info::LegalInfo)
    moves = Vector{Move}()

    #split into pinned and unpinned pieces, then run movegetter seperately on each
    unpinnedBB = pieceBB & ~(rookpins | bishoppins)
    pinnedBB = pinned(piece,pieceBB,rookpins,bishoppins)

    for (BB,rpins,bpins) in zip([pinnedBB,unpinnedBB],[rookpins,typemax(UInt64)],[bishoppins,typemax(UInt64)])
        for loc in identify_locations(BB)
            quiets,attacks = QAtt(piece,loc,all_pcs,enemy_pcs,rpins,bpins,info)

            quiet_moves = moves_from_location(val(piece),enemy_vec,quiets,loc,false)
            attack_moves = moves_from_location(val(piece),enemy_vec,attacks,loc,true)
        
            moves = vcat(moves,quiet_moves,attack_moves)
        end
    end
    return moves
end

"returns attack and quiet moves for pawns only if legal, based on checks and pins"
function get_moves(piece::Pawn,pieceBB,enemy_vec::Vector{UInt64},enemy_pcs,all_pcs,rookpins,bishoppins,info::LegalInfo)
    return []
end

"get lists of pieces and piece types, find locations of owned pieces and create a movelist of all legal moves"
function generate_moves(board::Boardstate)::Vector{Move}
    movelist = Vector{Move}()
    #implement 50 move rule and 3 position repetition
    if (board.Data.Halfmoves[end] >= 100) | (count(i->(i==board.ZHash),board.Data.ZHashHist) >= 3)
        board.State = Draw()
    else

    ally = ally_pieces(board)
    enemy = enemy_pieces(board)
    enemy_pcsBB = BBunion(enemy)
    all_pcsBB = BBunion(board.pieces)
    ally_pcsBB = all_pcsBB & ~enemy_pcsBB
    
    kingpos = identify_locations(ally[val(King())])[1]
    rookpins,bishoppins = detect_pins(kingpos,enemy,all_pcsBB,ally_pcsBB)
    legal_info = attack_info(enemy,all_pcsBB,kingpos,ally[val(King())])

    #run through pieces and BBs, adding moves to list
    for (type,pieceBB) in zip(piecetypes,ally)
        piece_moves = get_moves(type,pieceBB,enemy,
        enemy_pcsBB,all_pcsBB,rookpins,bishoppins,legal_info)
        movelist = vcat(movelist,piece_moves)
        
        #if multiple checks on king, only king can move
        if legal_info.attack_num > 1
            break
        end
    end

    if length(movelist) == 0
        if legal_info.attack_num > 0
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
