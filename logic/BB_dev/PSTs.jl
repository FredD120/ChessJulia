using logic

function save_PST(name,data)
    path = "$(pwd())/Engines/PST/"

    io = open(path*name*".txt", "w") do io
        for d in data
        println(io, d)
        end
    end
end

"Pawn square scores from whites perspective"
function PST(::Pawn)
    vals = Vector{Float32}(undef,64)

    for (i,val) in enumerate(vals)
        ind = i - 1
        r = rank(ind)
        f = file(ind)
        
        if r == 0 || r == 7 
            #0 and 7 are never reached, double pushing is generally better than single push
            vals[i] = 0
        else
            #encourage pawns off of starting rank and push towards promotion
            vals[i] = 15 * (r-2)
        end

        if r==3
            #early central pawn control
            if (f==3 || f==4)
                vals[i] += 10
            elseif (f==2 || f==5)
                vals[i] += 5
            end
        end

        if r==1
            #stay in front of king after castling
            if !((f==3) || (f==4))
                vals[i] += 20
            end
        elseif r==2
            #create escape square for caslted king
            if (f==0) || (f==7)
                vals[i] += 5
            end
        end
    end
    save_PST("pawn",vals)
end

function PST(::Knight)
    vals = Vector{Float32}(undef,64)

    for (i,val) in enumerate(vals)
        ind = i - 1
        r = rank(ind)
        f = file(ind)
        
        if (r == 0 || r == 7) || (f == 0 || f == 7)
            #Dissuade knight from being on edge
            vals[i] = -15
        elseif (r == 1 || r == 6) || (f == 1 || f == 6)
            #Neutral if one layer inside edge
            vals[i] = 0
        elseif (r == 2 || r == 5) || (f == 2 || f == 5)
            #Bonus for central control
            vals[i] = 10
        else
            #encourage taking centre early
            vals[i] = 20
        end
    end
    save_PST("knight",vals)
end

function PST(::Bishop)
    vals = Vector{Float32}(undef,64)

    for (i,val) in enumerate(vals)
        ind = i - 1
        r = rank(ind)
        f = file(ind)
        
        if (r == 0 || r == 7) || (f == 0 || f == 7)
            #Dissuade bishop from being on edge
            vals[i] = -15
        elseif (r == 1 || r == 6) || (f == 1 || f == 6)
            #Neutral if one layer inside edge
            vals[i] = 0
        else 
            #Bonus for central control
            vals[i] = 15
        end
        if (f==1)||(f==6)
            if (r==1) || (r==4)
                vals[i] += 10
            elseif r==2
                vals[i] += 15
            end
        end
    end
    save_PST("bishop",vals)
end

function PST(::Rook)
    vals = Vector{Float32}(undef,64)

    for (i,val) in enumerate(vals)
        ind = i - 1
        r = rank(ind)
        f = file(ind)
        
        if (r == 6 || r == 7)
            #Slightly encourage attacking enemy ranks
            vals[i] = 10
        elseif r == 0 
            #Centralise and hopefully castle
            if (f==3) || (f==4)
                vals[i] = 15
            end
        end
    end
    save_PST("rook",vals)
end

function PST(::Queen)
    vals = Vector{Float32}(undef,64)

    for (i,val) in enumerate(vals)
        ind = i - 1
        r = rank(ind)
        f = file(ind)
        
        if (r == 0 || r == 7) || (f == 0 || f == 7)
            #Dissuade queen from being on edge
            vals[i] = -15
        elseif (r == 1 || r == 6) || (f == 1 || f == 6)
            #Neutral if one layer inside edge
            vals[i] = 0
        else 
            #Bonus for central control
            vals[i] = 5
        end

        if r==0
            #dont discourage staying on back rank too much
            vals[i] += 10
        end
    end
    save_PST("queen",vals)
end

function PST(::King)
    vals = Vector{Float32}(undef,64)

    for (i,val) in enumerate(vals)
        ind = i - 1
        r = rank(ind)
        f = file(ind)
        
        if r > 2 
            #Dissuade king from advancing
            vals[i] = -30
        elseif r == 2 
            #Can move up if necessary
            vals[i] = -20
        end

        if r==0
            #encourage castling
            if (f==1) || (f==6)
                vals[i] += 30
            #hide behind pawns
            elseif (f==0) || (f==2) || (f==5) || (f==7)
                vals[i] += 10
            end
        end
    end
    save_PST("king",vals)
end

PST(King())
PST(Queen())
PST(Rook())
PST(Bishop())
PST(Knight())
PST(Pawn())