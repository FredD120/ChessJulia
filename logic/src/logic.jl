module logic

###TO THINK ABOUT###
#How much data is being passed around by functions unnecessarily?
#Is there code branching due to type instability?
#Decide function once then repeatedly call it (functions have different types -> type instability)
#Vs call function repeatedly and choose each time (for only two cheap functions is ok)
#Can force definite types for function dispatch, will create union of types that are slow if too many

###FEATURES
#Include PSTs, updated in make/unmake by create! and destroy!
#Generate attacks seperately for quiescence 

###OPTIMISATIONS
#Fold move struct into single 32 bit int and create helper functions to decode


#=
To check generated code:
@code_llvm
@code_native
@code_warntype
=#

export GUIposition, Boardstate, Move, make_move!, unmake_move!, UCImove,
Neutral, Loss, Draw, generate_moves, Move, Whitesmove, perft, Piece,
King, Queen, Rook, Bishop, Knight, Pawn, White, Black, white, black, val, piecetypes,
NOFLAG, KCASTLE, QCASTLE, EPFLAG, PROMQUEEN, PROMROOK, PROMBISHOP,
PROMKNIGHT, DPUSH, ally_pieces, enemy_pieces, identify_locations, count_pieces,
NULLMOVE, rank, file

using InteractiveUtils
using JLD2
using Random
using StaticArrays
rng = Xoshiro(2955)

const White = UInt8(0)
const Black = UInt8(6)
const NULL_PIECE = UInt8(0)

abstract type Piece end
struct King <:Piece end
struct Queen <:Piece end
struct Rook <:Piece end
struct Bishop <:Piece end
struct Knight <:Piece end
struct Pawn <:Piece end

struct white end
struct black end

const piecetypes = [King(),Queen(),Rook(),Bishop(),Knight(),Pawn()]

"Return index associated with piecetype"
val(::King) = UInt8(1)
val(::Queen) = UInt8(2)
val(::Rook) = UInt8(3)
val(::Bishop) = UInt8(4)
val(::Knight) = UInt8(5)
val(::Pawn) = UInt8(6)

"Return index shift associated with colour"
val(::white) = UInt8(0)
val(::black) = UInt8(6)

Base.string(::King) = "King"
Base.string(::Queen) = "Queen"
Base.string(::Rook) = "Rook"
Base.string(::Bishop) = "Bishop"
Base.string(::Knight) = "Knight"
Base.string(::Pawn) = "Pawn"

const ZobristKeys = rand(rng,UInt64,12*64+9)

const NOFLAG = UInt8(0)
const KCASTLE = UInt8(1)
const QCASTLE = KCASTLE + 1
const EPFLAG = UInt8(3)
const DPUSH = UInt8(4)
const PROMQUEEN = UInt8(5)
const PROMROOK = UInt8(6)
const PROMBISHOP = UInt8(7)
const PROMKNIGHT = UInt8(8)

struct Promote end

"Get a rank from a 0-63 index"
rank(ind) = 7 - (ind >> 3)
"Get a file from a 0-63 index"
file(ind) = ind % 8

struct Move
    piece_type::UInt8
    from::UInt8
    to::UInt8
    capture_type::UInt8
    flag::UInt8
end

const NULLMOVE = Move(0,0,0,0,0)

Base.show(io::IO,m::Move) = print(io,"From=$(Int(m.from));To=$(Int(m.to));PieceId=$(Int(m.piece_type));Capture ID=$(Int(m.capture_type));Flag=$(Int(m.flag))")

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
    king::SVector{64,UInt64}
    knight::SVector{64,UInt64}
    CRightsMask::SVector{6,UInt8}
    CastleCheck::SVector{6,UInt64}
end

"constructor for Move_BB that reads all moves from txt files"
function Move_BB()
    king_mvs = read_txt("king")
    knight_mvs = read_txt("knight")
    Crights = [0b1100,0b1110,0b1101,0b0011,0b1011,0b0111]
    castle_check = read_txt("CastleCheck")
    return Move_BB(king_mvs,knight_mvs,Crights,castle_check)
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

    MagicVec = @SVector [Magic(Magics[i],Masks[i],BitShifts[i],AttackVec[i]) for i in 1:64]
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
    Castling::Vector{UInt8}
    CastleCount::Vector{UInt8}
    EnPassant::Vector{UInt64}
    EPCount::Vector{UInt8}
    ZHashHist::Vector{UInt64}
end

mutable struct Boardstate
    pieces::Vector{UInt64}
    ColourIndex::UInt8
    Castle::UInt8
    EnPass::UInt64
    State::GameState
    ZHash::UInt64
    MoveHist::Vector{Move}
    Data::BoardData
end

"Helper function to determine whose move it is"
Whitesmove(ColourIndex::UInt8) = ifelse(ColourIndex == 0, true, false)

ColID(ColourIndex::UInt8) = ColourIndex % 5

"Helper function to return opposite colour index"
Opposite(ColourIndex::UInt8)::UInt8 = (ColourIndex+6)%12

"returns a list of numbers between 0 and 63 to indicate positions on a chessboard"
function identify_locations(pieceBB::Integer)::Vector{UInt8}
    locations = Vector{UInt8}()
    temp_BB = pieceBB
    while temp_BB != 0
        loc = trailing_zeros(temp_BB) #find 0-indexed location of least significant bit in BB
        push!(locations,loc)
        temp_BB &= temp_BB - 1        #trick to remove least significant bit
    end
    return locations
end

"Define start of iterator through locations in a bitboard"
function Base.iterate(BB::UInt64) 
    if BB == 0
        return nothing
    else
        next_state = BB & (BB-1)
        first_item = trailing_zeros(BB)
        return first_item,next_state
    end
end

"Returns next (item, state) in iterator through locations in a bitboard"
function Base.iterate(BB::UInt64,state::UInt64) 
    if state == 0
        return nothing
    else
        next_state = state & (state-1)
        next_item = trailing_zeros(state)
        return next_item,next_state
    end
end

"Define length of occupied positions in BB"
Base.length(BB::UInt64) = count_ones(BB)

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

"Count the total number of pieces in a vector of bitboards"
function count_pieces(pieces::Vector{UInt64})
    count = 0
    for BB in pieces
        count += count_ones(BB)
    end
    return count
end

"Helper function when constructing a boardstate"
function place_piece!(pieces::Vector{UInt64},pieceID,pos)
    pieces[pieceID] = setone(pieces[pieceID],pos)
end

"Helper function to modify Zhash based on castle rights"
function Zhashcastle!(ZHash,castling)
    #use last rank of black pawns and 8 extra indices (0⋜castling⋜15)
    ZHash ⊻= ZobristKeys[end - 16 + castling]
end

"Helper function to modify Zhash based on en-passant"
function ZhashEP!(ZHash,enpassant)
    for EP in enpassant
        file = EP % 8
        #use first rank of black pawns
        ZHash ⊻= ZobristKeys[64*(11)+file+1]
    end
end

"Returns zobrist key associated with a coloured piece at a location"
ZKey_piece(CpieceID,pos) = ZobristKeys[64*(CpieceID-1)+pos+1]

"Returns zobrist key associated with whose turn it is (switched on if black)"
ZKeyColour() = ZobristKeys[end]

"Generate Zobrist hash of a boardstate"
function generate_hash(pieces,Whitesmove,castling,enpassant)
    ZHash = UInt64(0)
    for (pieceID,pieceBB) in enumerate(pieces)
        for loc in pieceBB
            ZHash ⊻= ZKey_piece(pieceID,loc)
        end
    end

    #the rest of this data is packed in using the fact that neither
    #black nor white pawns will exist on first or last rank
    ZhashEP!(ZHash,enpassant)
    Zhashcastle!(ZHash,castling)

    if !Whitesmove
        ZHash ⊻= ZKeyColour()
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
                Castling = setone(Castling,0)
            elseif c == 'Q'
                Castling = setone(Castling,1)
            elseif c == 'k'
                Castling = setone(Castling,2)
            elseif c == 'q'
                Castling = setone(Castling,3)
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
                     Vector{UInt8}([Castling]),Vector{UInt8}([0]),
                     Vector{UInt64}([EnPassant]),Vector{UInt8}([0]),
                     Vector{UInt64}([Zobrist]))

    Boardstate(pieces,ColourIndex,Castling,EnPassant,Neutral(),Zobrist,MoveHistory,data)
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

"Masked 4-bit integer representing king- and queen-side castling rights for one side"
function get_Crights(castling,ColID,KorQside)
    #ColID must be 0 for white and 1 for black
    #KorQside allows masking out of only king/queen side
    #for a given colour, =0 if both, 1 = king, 2 = queen
    return castling & moveset.CRightsMask[3*ColID+KorQside+1]
end

"Returns a single bitboard representing the positions of an array of pieces"
function BBunion(piece_vec::Vector{UInt64})
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

"Returns BB containing attacking moves assuming all pieces in BB are pawns"
function possible_moves(::Pawn,pawnBB,Whitesmove)
    pawn_push = cond_push(pawnBB,Whitesmove)
    return attack_left(pawn_push) | attack_right(pawn_push)
end

"checks enemy pieces to see if any are attacking the king square, returns BB of attackers"
function attack_pcs(pc_list::Vector{UInt64},all_pcs::UInt64,location::Integer,Whitesmove)::UInt64
    attacks = UInt64(0)
    knightmoves = possible_moves(Knight(),location,all_pcs)
    attacks |= (knightmoves & pc_list[val(Knight())])

    rookmoves = possible_moves(Rook(),location,all_pcs)
    rookattacks = (rookmoves & (pc_list[val(Rook())] | pc_list[val(Queen())]))
    attacks |= rookattacks

    bishopmoves = possible_moves(Bishop(),location,all_pcs)
    bishopattacks = (bishopmoves & (pc_list[val(Bishop())] | pc_list[val(Queen())]))
    attacks |= bishopattacks

    pawnattacks = possible_moves(Pawn(),UInt64(1)<<location,Whitesmove)
    attacks |= pawnattacks & pc_list[val(Pawn())]

    return attacks
end

"Bitboard of all squares being attacked by a side"
function all_poss_moves(pc_list::Vector{UInt64},all_pcs,Whitesmove::Bool)::UInt64
    attacks = UInt64(0)

    for (pieceBB,type) in zip(pc_list[1:end-1],piecetypes[1:end-1])
        for location in pieceBB
            attacks |= possible_moves(type,location,all_pcs)
        end
    end
    attacks |= possible_moves(Pawn(),pc_list[val(Pawn())],!Whitesmove)
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
    for loc in rookpins
        #add squares on pin line to pinning BB
        rookpins |= rook_no_blocks & possible_moves(Rook(),loc,blocks_removed)
    end

    #same but for bishops
    bishop_no_blocks = possible_moves(Bishop(),pos,blocks_removed) 
    bpin_attacks = bishop_no_blocks & ~slide_attacks
    bishoppins = bpin_attacks & (pc_list[val(Bishop())] | pc_list[val(Queen())])
    for loc in bishoppins
        bishoppins |= bishop_no_blocks & possible_moves(Bishop(),loc,blocks_removed)
    end

    return rookpins,bishoppins
end

"returns struct containing info on attacks, blocks and pins of king by enemy piecelist"
function attack_info(pc_list::Vector{UInt64},all_pcs::UInt64,position,KingBB,Whitesmove)::LegalInfo
    attacks = typemax(UInt64)
    blocks = UInt64(0)
    attacker_num = 0

    #construct BB of all enemy attacks, must remove king when checking if square is attacked
    all_except_king = all_pcs & ~(KingBB)
    attacked_sqs = all_poss_moves(pc_list,all_except_king,Whitesmove)

    #if king not under attack, dont need to find attacking pieces or blockers
    if KingBB & attacked_sqs == UInt64(0) 
        blocks = typemax(UInt64)
    else
        attacks = attack_pcs(pc_list,all_pcs,position,Whitesmove)
        attacker_num = count_ones(attacks)
        #if only a single sliding piece is attacking the king, it can be blocked
        if attacker_num == 1
            for piece in [Rook(),Bishop()]
                kingmoves = possible_moves(piece,position,all_pcs)
                slide_attckers = kingmoves & (pc_list[val(piece)] | pc_list[val(Queen())])
                for attack_pos in slide_attckers
                    attackmoves = possible_moves(piece,attack_pos,all_pcs)
                    blocks |= attackmoves & kingmoves
                end
            end
        end
    end
    
    return LegalInfo(attacks,blocks,attacked_sqs,attacker_num)
end

"create a castling move where from and to is the rook to move"
function create_castle(KorQ,WorB)
    #KorQ is 0 if kingside, 1 if queenside 
    #WorB is 0 if white, 1 if black
    from = UInt8(63 - 7*KorQ - WorB*56)
    to = from - 2 + 5*KorQ
    return Move(val(King()),from,to,NULL_PIECE,KCASTLE+KorQ)
end

"creates a move from a given location using the Move struct, with flag for attacks"
function moves_from_location!(type::UInt8,moves,enemy_pcs::Vector{UInt64},destinations::UInt64,origin,isattack::Bool)
    for loc in destinations
        attacked_pieceID = NULL_PIECE
        if isattack
            #move struct needs info on piece being attacked
            attacked_pieceID = identify_piecetype(enemy_pcs,loc)
        end
        push!(moves,Move(type,origin,loc,attacked_pieceID,NOFLAG))
    end
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
function legal_moves(piece::King,loc,all_pcs,info::LegalInfo)
    poss_moves = possible_moves(piece,loc,all_pcs)
    #Filter out moves that put king in check
    legal_moves = poss_moves & ~info.attack_sqs
    return legal_moves
end

"Filter possible moves for legality for Knight"
function legal_moves(piece::Knight,loc,all_pcs,info::LegalInfo)
    poss_moves = possible_moves(piece,loc,all_pcs)
    #Filter out knight moves that don't block/capture if in check
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

"Bitboard logic to get attacks and quiets for king from legal moves"
function QAtt(legal,all_pcs,enemy_pcs)
    attacks = attack_moves(legal,enemy_pcs)
    quiets = quiet_moves(legal,all_pcs)
    return quiets,attacks
end

"Bishop can only move if pinned diagonally"
pinned(::Bishop,pieceBB,bishoppins) = pieceBB & bishoppins

"Rook can only move if pinned vertic/horizontally"
pinned(::Rook,pieceBB,rookpins) = pieceBB & rookpins

"returns attack and quiet moves only if legal, based on checks and pins"
function get_moves!(piece::Queen,moves,pieceBB,enemy_vec::Vector{UInt64},enemy_pcs,all_pcs,rookpins,bishoppins,info::LegalInfo)
    #split into pinned and unpinned pieces, then run movegetter seperately on each
    unpinnedBB = pieceBB & ~(rookpins | bishoppins)
    RpinnedBB = pinned(Rook(),pieceBB,rookpins)
    BpinnedBB = pinned(Bishop(),pieceBB,bishoppins)

    for (BB,type,rpins,bpins) in zip([unpinnedBB,RpinnedBB,BpinnedBB],[Queen(),Rook(),Bishop()],
        [typemax(UInt64),rookpins,typemax(UInt64)],[typemax(UInt64),typemax(UInt64),bishoppins])
        for loc in BB
            legal = legal_moves(type,loc,all_pcs,rpins,bpins,info)
            quiets,attacks = QAtt(legal,all_pcs,enemy_pcs)

            moves_from_location!(val(piece),moves,enemy_vec,quiets,loc,false)
            moves_from_location!(val(piece),moves,enemy_vec,attacks,loc,true)
        end
    end
end

"returns attack and quiet moves only if legal for rook, based on checks and pins"
function get_moves!(piece::Rook,moves,pieceBB,enemy_vec::Vector{UInt64},enemy_pcs,all_pcs,rookpins,bishoppins,info::LegalInfo)
    #split into pinned and unpinned pieces, then run movegetter seperately on each
    unpinnedBB = pieceBB & ~(rookpins | bishoppins)
    pinnedBB = pinned(piece,pieceBB,rookpins)

    for (BB,rpins) in zip([pinnedBB,unpinnedBB],[rookpins,typemax(UInt64)])
        for loc in BB
            legal = legal_moves(piece,loc,all_pcs,rpins,typemax(UInt64),info)
            quiets,attacks = QAtt(legal,all_pcs,enemy_pcs)

            moves_from_location!(val(piece),moves,enemy_vec,quiets,loc,false)
            moves_from_location!(val(piece),moves,enemy_vec,attacks,loc,true)
        end
    end
end

"returns attack and quiet moves only if legal for bishop, based on checks and pins"
function get_moves!(piece::Bishop,moves,pieceBB,enemy_vec::Vector{UInt64},enemy_pcs,all_pcs,rookpins,bishoppins,info::LegalInfo)
    #split into pinned and unpinned pieces, then run movegetter seperately on each
    unpinnedBB = pieceBB & ~(rookpins | bishoppins)
    pinnedBB = pinned(piece,pieceBB,bishoppins)

    for (BB,bpins) in zip([pinnedBB,unpinnedBB],[bishoppins,typemax(UInt64)])
        for loc in BB
            legal = legal_moves(piece,loc,all_pcs,typemax(UInt64),bpins,info)
            quiets,attacks = QAtt(legal,all_pcs,enemy_pcs)

            moves_from_location!(val(piece),moves,enemy_vec,quiets,loc,false)
            moves_from_location!(val(piece),moves,enemy_vec,attacks,loc,true)
        end
    end
end

"returns attack and quiet moves only if legal for knight, based on checks and pins"
function get_moves!(piece::Knight,moves,pieceBB,enemy_vec::Vector{UInt64},enemy_pcs,all_pcs,rookpins,bishoppins,info::LegalInfo)
    #split into pinned and unpinned pieces, only unpinned knights can move
    unpinnedBB = pieceBB & ~(rookpins | bishoppins)
    for loc in unpinnedBB
        legal = legal_moves(piece,loc,all_pcs,info)
        quiets,attacks = QAtt(legal,all_pcs,enemy_pcs)

        moves_from_location!(val(piece),moves,enemy_vec,quiets,loc,false)
        moves_from_location!(val(piece),moves,enemy_vec,attacks,loc,true)
    end
end

"returns attacks, quiet moves and castles for king only if legal, based on checks"
function get_moves!(piece::King,moves,pieceBB,enemy_vec::Vector{UInt64},enemy_pcs,all_pcs,castlrts,colID,info::LegalInfo)
    for loc in pieceBB
        legal = legal_moves(piece,loc,all_pcs,info)
        quiets,attacks = QAtt(legal,all_pcs,enemy_pcs)

        moves_from_location!(val(piece),moves,enemy_vec,quiets,loc,false)
        moves_from_location!(val(piece),moves,enemy_vec,attacks,loc,true)
    end
    #cannot castle out of check
    if info.attack_num == 0
        #index into lookup table containing squares that must be free/not in check to castle
        #must mask out opponent's castle rights
        for castleID in identify_locations(get_Crights(castlrts,(colID+1)%2,0))
            castleattack = moveset.CastleCheck[castleID+1]
            blockId = castleID%2 # only queenside castle (=1) has extra block squares
            #white queen blockers are at index 5, black queen blockers are at index 6
            castleblock = moveset.CastleCheck[castleID+blockId*(2+(castleID%3))+1]
            if (castleblock & all_pcs == 0) & (castleattack & info.attack_sqs == 0)
                push!(moves,create_castle(castleID%2,colID))
            end
        end
    end
end

"use bitshifts to push all white/black pawns at once"
cond_push(pawnBB,isWhite) = ifelse(isWhite,pawnBB >> 8,pawnBB << 8)

const white_masks = (
        doublepush = UInt64(0xFF0000000000),
        promote = UInt64(0xFF),
        shift =  8
)

const black_masks = (
        doublepush = UInt64(0xFF0000),
        promote = UInt64(0xFF00000000000000),
        shift =  -8
)

attack_left(pieceBB) = (pieceBB >> 1) & UInt64(0x7F7F7F7F7F7F7F7F)

attack_right(pieceBB) = (pieceBB << 1) & UInt64(0xFEFEFEFEFEFEFEFE)

"appends 4 promotion moves"
function append_moves!(moves,piece_type,from,to,capture_type,::Promote)
    for flag in [PROMQUEEN,PROMROOK,PROMBISHOP,PROMKNIGHT]
        push!(moves,Move(piece_type,from,to,capture_type,flag))
    end
end

"appends a non-promote move with a given flag"
function append_moves!(moves,piece_type,from,to,capture_type,flag::UInt8)
    push!(moves,Move(piece_type,from,to,capture_type,flag))
end

"Create list of pawn push moves with a given flag"
function push_moves!(moves,singlepush,promotemask,shift,blocks,flag)
    for q1 in (singlepush & blocks & promotemask)
        append_moves!(moves,val(Pawn()),q1+shift,q1,NULL_PIECE,flag)
    end
end

"Create list of double pawn push moves"
function push_moves!(moves,doublepush,shift,blocks)
    for q2 in (doublepush & blocks)
        push!(moves,Move(val(Pawn()),q2+2*shift,q2,NULL_PIECE,DPUSH))
    end
end

"Create list of pawn capture moves with a given flag"
function capture_moves!(moves,leftattack,rightattack,promotemask,shift,enemy_pcs,checks,enemy_vec::Vector{UInt64},flag)
    for la in (leftattack & enemy_pcs & promotemask & checks)
        attack_pcID = identify_piecetype(enemy_vec,la)
        append_moves!(moves,val(Pawn()),la+shift+1,la,attack_pcID,flag)
    end
    for ra in (rightattack & enemy_pcs & promotemask & checks)
        attack_pcID = identify_piecetype(enemy_vec,ra)
        append_moves!(moves,val(Pawn()),ra+shift-1,ra,attack_pcID,flag)
    end
end

"returns false if it fails edge case where EP exposes attack on king"
function EPedgecase(from,EPcap,kingpos,all_pcs,enemy_vec)
    #test if king is on same rank as EP pawn
    if rank(from) == rank(kingpos)
        #all pcs BB after en-passant
        after_EP = setzero(setzero(all_pcs,from),EPcap)
        kingrookmvs = possible_moves(Rook(),kingpos,after_EP)
        if (kingrookmvs & (enemy_vec[val(Rook())] | enemy_vec[val(Queen())])) > 0
            return false
        end
    end
    return true
end

"Check legality of en-passant before adding it to move list"
function push_EP!(moves,from,to,shift,checks,all_pcs,enemy_vec,kingpos)
    EPcap = to+shift
    if checks & (UInt64(1) << EPcap) > 0
        if EPedgecase(from,EPcap,kingpos,all_pcs,enemy_vec)
            push!(moves,Move(val(Pawn()),from,to,val(Pawn()),EPFLAG))
        end
    end
end

"Create list of pawn en-passant moves"
function EP_moves!(movelist,leftattack,rightattack,shift,EP_sqs,checks,all_pcs,enemy_vec,kingpos)
    for la in (leftattack & EP_sqs)  
        push_EP!(movelist,la+shift+1,la,shift,checks,all_pcs,enemy_vec,kingpos)
    end
    for ra in (rightattack & EP_sqs)
        push_EP!(movelist,ra+shift-1,ra,shift,checks,all_pcs,enemy_vec,kingpos)
    end
end

"returns attack and quiet moves for pawns only if legal, based on checks and pins"
function get_moves!(::Pawn,movelist,pieceBB,enemy_vec::Vector{UInt64},enemy_pcs,all_pcs,enpassBB,rookpins,bishoppins,whitesmove,kingpos,info::LegalInfo)
    pawnMasks = ifelse(whitesmove,white_masks,black_masks)

    #split into pinned and unpinned pieces, then run movegetter seperately on each
    unpinnedBB = pieceBB & ~(rookpins | bishoppins)
    RpinnedBB = pinned(Rook(),pieceBB,rookpins)
    BpinnedBB = pinned(Bishop(),pieceBB,bishoppins)

    #push once and remove any that are blocked
    pushpawn1 = cond_push(unpinnedBB,whitesmove)
    legalpush1 = quiet_moves(pushpawn1,all_pcs)
    pushpinned = cond_push(RpinnedBB,whitesmove)
    legalpush1 |= quiet_moves(pushpinned,all_pcs) & rookpins

    #push twice if possible
    pushpawn2 = cond_push(legalpush1 & pawnMasks.doublepush,whitesmove)
    legalpush2 = quiet_moves(pushpawn2,all_pcs)

    #shift left and right to attack
    attackleft = attack_left(pushpawn1)
    attackright = attack_right(pushpawn1)

    Bpush = cond_push(BpinnedBB,whitesmove)
    Battackleft = attack_left(Bpush)
    Battackright = attack_right(Bpush)

    #combine with attacks pinned by a bishop
    attackleft |= Battackleft & bishoppins
    attackright |= Battackright & bishoppins
    
    #add non-promote pushes, promote pushes, double pushes, non-promote captures, promote captures and en-passant
    push_moves!(movelist, legalpush1, ~pawnMasks.promote, pawnMasks.shift, info.blocks, NOFLAG),
    push_moves!(movelist, legalpush1, pawnMasks.promote, pawnMasks.shift, info.blocks, Promote()),
    push_moves!(movelist, legalpush2, pawnMasks.shift, info.blocks),
    capture_moves!(movelist, attackleft, attackright, ~pawnMasks.promote,pawnMasks.shift,enemy_pcs,info.checks,enemy_vec,NOFLAG),
    capture_moves!(movelist, attackleft, attackright, pawnMasks.promote,pawnMasks.shift,enemy_pcs,info.checks,enemy_vec,Promote()),
    EP_moves!(movelist, attackleft, attackright, pawnMasks.shift,enpassBB,info.checks,all_pcs,enemy_vec,kingpos)
end

"get lists of pieces and piece types, find locations of owned pieces and create a movelist of all legal moves"
function generate_moves(board::Boardstate)::Vector{Move}
    movelist = Vector{Move}()
    sizehint!(movelist,40)

    #implement 50 move rule and 3 position repetition
    if (board.Data.Halfmoves[end] >= 100) || (count(i->(i==board.ZHash),board.Data.ZHashHist) >= 3)
        board.State = Draw()
    else

    ally = ally_pieces(board)
    enemy = enemy_pieces(board)
    enemy_pcsBB = BBunion(enemy)
    all_pcsBB = BBunion(board.pieces)
    ally_pcsBB = all_pcsBB & ~enemy_pcsBB
    kingBB = ally[val(King())]
    isWhite = Whitesmove(board.ColourIndex)
    
    kingpos = trailing_zeros(kingBB)
    rookpins,bishoppins = detect_pins(kingpos,enemy,all_pcsBB,ally_pcsBB)
    legal_info = attack_info(enemy,all_pcsBB,kingpos,kingBB,isWhite)

    get_moves!(King(),movelist,kingBB,enemy,enemy_pcsBB,all_pcsBB,
    board.Castle,ColID(board.ColourIndex),legal_info)

    #if multiple checks on king, only king can move
    if legal_info.attack_num <= 1
        #run through pieces and BBs, adding moves to list
        for (type,pieceBB) in zip(piecetypes[2:end-1],ally[2:end-1])
            get_moves!(type,movelist,pieceBB,enemy,
            enemy_pcsBB,all_pcsBB,rookpins,bishoppins,legal_info)
        end
        get_moves!(Pawn(),movelist,ally[end],enemy,enemy_pcsBB,all_pcsBB,board.EnPass,
        rookpins,bishoppins,isWhite,kingpos,legal_info)
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
    B.ZHash ⊻= ZKey_piece(CpieceID,pos)
end

"utilises setone to create a piece in a position"
function create_piece!(B::Boardstate,CpieceID,pos)
    B.pieces[CpieceID] = setone(B.pieces[CpieceID],pos)
    B.ZHash ⊻= ZKey_piece(CpieceID,pos)
end

"utilises create and destroy to move single piece"
function move_piece!(B::Boardstate,CpieceID,from,to)
    destroy_piece!(B,CpieceID,from)
    create_piece!(B,CpieceID,to)
end

"switch to opposite colour and update hash key"
function swap_player!(board)
    board.ColourIndex = Opposite(board.ColourIndex)
    board.ZHash ⊻= ZKeyColour()
end

"make a kingside castle"
function Kcastle!(B::Boardstate,CpieceID)
    kingpos = trailing_zeros(B.pieces[CpieceID])
    move_piece!(B,CpieceID,kingpos,kingpos+2)
end 

"make a queenside castle"
function Qcastle!(B::Boardstate,CpieceID)
    kingpos = trailing_zeros(B.pieces[CpieceID])
    move_piece!(B,CpieceID,kingpos,kingpos-2)
end

"update castling rights and Zhash"
function updateCrights!(board::Boardstate,ColId,side)
    #remove ally castling rights by &-ing with opponent mask
    #side is king=1, queen=2, both=0
    Zhashcastle!(board.ZHash,board.Castle)
    board.Castle = get_Crights(board.Castle,ColId,side)
    Zhashcastle!(board.ZHash,board.Castle)
end

"Decide which piecetype to promote to"
function promote_type(flag)
    if flag == PROMQUEEN
        return val(Queen())
    elseif flag == PROMROOK
        return val(Rook())
    elseif flag == PROMBISHOP
        return val(Bishop())
    elseif flag == PROMKNIGHT
        return val(Knight())
    end
end

"Returns location of en-passant and also pawn being captured by en-passant"
EPlocation(moveloc,ColId) = ifelse(ColId==0,moveloc+8,moveloc-8)

"modify boardstate by making a move. increment halfmove count. add move to MoveHist. update castling rights"
function make_move!(move::Move,board::Boardstate)
    #0 = white, 1 = black
    ColId = ColID(board.ColourIndex)

    #deal with castling
    if (move.flag == KCASTLE) | (move.flag == QCASTLE)
        rookID = board.ColourIndex + val(Rook())
        move_piece!(board,rookID,move.from,move.to)
        updateCrights!(board,ColId,0)
        CpieceID = board.ColourIndex + val(King())
        if move.flag == KCASTLE
            Kcastle!(board,CpieceID)
        else
            Qcastle!(board,CpieceID)
        end
        #castling does not reset halfmove count
        board.Data.Halfmoves[end] += 1

    #update castling rights if not castling    
    else
        if board.Castle > 0
            if move.piece_type == val(King())
                updateCrights!(board,ColId,0)
            else
                #lose self castle rights
                if move.from == 63-56*ColId     #kingside
                    updateCrights!(board,ColId,1)
                elseif move.from == 56-56*ColId #queenside
                    updateCrights!(board,ColId,2)
                end
            end
            #remove enemy castle rights
            if move.to == 7+56*ColId        #kingside
                updateCrights!(board,(ColId+1)%2,1)
            elseif move.to == 56*ColId      #queenside
                updateCrights!(board,(ColId+1)%2,2)
            end
        end
        #deal with promotions, always reset halfmove clock
        if (move.flag == PROMQUEEN)|(move.flag == PROMROOK)|(move.flag == PROMBISHOP)|(move.flag == PROMKNIGHT)
            push!(board.Data.Halfmoves,0)
            destroy_piece!(board,board.ColourIndex+move.piece_type,move.from)
            create_piece!(board,board.ColourIndex+promote_type(move.flag),move.to)

            if move.capture_type > 0
                destroy_piece!(board,Opposite(board.ColourIndex)+move.capture_type,move.to)
            end

        else #no flag, en-passant, double push
            move_piece!(board,board.ColourIndex+move.piece_type,move.from,move.to)

            if move.capture_type > 0
                destroy_loc = move.to
                if move.flag == EPFLAG
                    destroy_loc = EPlocation(destroy_loc,ColId)
                end
                destroy_piece!(board,Opposite(board.ColourIndex)+move.capture_type,destroy_loc)
                push!(board.Data.Halfmoves,0)
            elseif move.piece_type == val(Pawn())
                push!(board.Data.Halfmoves,0)
            else
                board.Data.Halfmoves[end] += 1
            end
        end
    end

    #update EnPassant
    if move.flag == DPUSH
        location = EPlocation(move.to,ColId)
        board.EnPass = UInt64(1) << location
        push!(board.Data.EnPassant,board.EnPass)
        push!(board.Data.EPCount,0)
    elseif board.EnPass > 0
        board.EnPass = UInt64(0)
        push!(board.Data.EnPassant,board.EnPass)
        push!(board.Data.EPCount,0)
    else
        board.Data.EPCount[end] += 1
    end

    swap_player!(board)
    push!(board.MoveHist,move)
    push!(board.Data.ZHashHist,board.ZHash)

    #check if caslting rights have changed
    if board.Castle == board.Data.Castling[end]
        board.Data.CastleCount[end] += 1
    else
        #add new castling rights to history stack
        push!(board.Data.Castling,board.Castle)
        push!(board.Data.CastleCount,0)
    end
end

"unmakes last move on MoveHist stack. restore halfmoves, EP squares and castle rights"
function unmake_move!(board::Boardstate)
    OppCol = Opposite(board.ColourIndex)
    if length(board.MoveHist) > 0
        board.State = Neutral()
        move = board.MoveHist[end]

        if (move.flag == KCASTLE)|(move.flag == QCASTLE)
            rookID = OppCol + val(Rook())
            move_piece!(board,rookID,move.to,move.from)
            CpieceID = OppCol + val(King())
            #unmaking a kingside castle is the same as a queenside castle and vice-versa
            if move.flag == KCASTLE
                Qcastle!(board,CpieceID)
            else
                Kcastle!(board,CpieceID)
            end
        
        #deal with everything other than castling
        else
            if (move.flag==NOFLAG)|(move.flag==DPUSH)|(move.flag==EPFLAG)
                move_piece!(board,OppCol+move.piece_type,move.to,move.from)

                if move.capture_type > 0
                    create_loc = move.to
                    if move.flag == EPFLAG
                        create_loc = EPlocation(create_loc,ColID(OppCol))
                    end
                    create_piece!(board,board.ColourIndex+move.capture_type,create_loc)
                end
            else #deal with promotions
                create_piece!(board,OppCol+move.piece_type,move.from)
                destroy_piece!(board,OppCol+promote_type(move.flag),move.to)

                if move.capture_type > 0
                    create_piece!(board,board.ColourIndex+move.capture_type,move.to)
                end
            end
        end

        swap_player!(board)
        pop!(board.MoveHist)

        #update data struct with halfmoves, en-passant, hash and castling
        pop!(board.Data.ZHashHist)
        board.ZHash = board.Data.ZHashHist[end]

        if board.Data.Halfmoves[end] > 0 
            board.Data.Halfmoves[end] -= 1
        else
            pop!(board.Data.Halfmoves)
        end

        if board.Data.CastleCount[end] == 0
            pop!(board.Data.CastleCount)
            pop!(board.Data.Castling)
            board.Castle = board.Data.Castling[end]
        else
            board.Data.CastleCount[end] -= 1
        end

        if board.Data.EPCount[end] == 0
            pop!(board.Data.EPCount)
            pop!(board.Data.EnPassant)
            board.EnPass = board.Data.EnPassant[end]
        else
            board.Data.EPCount[end] -= 1
        end  
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
