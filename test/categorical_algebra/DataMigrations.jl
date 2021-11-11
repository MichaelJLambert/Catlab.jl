module TestDataMigrations
using Test

using Catlab, Catlab.Theories, Catlab.Graphs, Catlab.CategoricalAlgebra
using Catlab.Programs.DiagrammaticPrograms
using Catlab.Graphs.BasicGraphs: TheoryGraph, TheoryReflexiveGraph,
  TheorySymmetricGraph, TheoryWeightedGraph
using Catlab.Graphs.BipartiteGraphs: TheoryUndirectedBipartiteGraph

# Pullback migration
####################

@present TheoryDDS(FreeSchema) begin
  X::Ob
  Φ::Hom(X,X)
end

@abstract_acset_type AbstractDDS
@acset_type DDS(TheoryDDS, index=[:Φ]) <: AbstractDDS

h = Graph(3)
add_parts!(h, :E, 3, src = [1,2,3], tgt = [2,3,1])

# Identity data migration.
@test h == migrate(Graph, h, Dict(:V => :V, :E => :E),
                   Dict(:src => :src, :tgt => :tgt))

# Migrate DDS → Graph.
dds = DDS()
add_parts!(dds, :X, 3, Φ=[2,3,1])
X = TheoryDDS[:X]
@test h == migrate(Graph, dds, Dict(:V => :X, :E => :X),
                   Dict(:src => id(X), :tgt => :Φ))

h2 = copy(h)
migrate!(h2, dds, Dict(:V => :X, :E => :X),
                  Dict(:src => id(X), :tgt => :Φ))
@test h2 == ob(coproduct(h, h))

# Migrate DDS → DDS by advancing four steps.
@test dds == migrate(DDS, dds, Dict(:X => :X),
                     Dict(:Φ => [:Φ, :Φ, :Φ, :Φ]))

@present TheoryLabeledDDS <: TheoryDDS begin
  Label::AttrType
  label::Attr(X, Label)
end
@acset_type LabeledDDS(TheoryLabeledDDS, index=[:Φ, :label])

S, ϕ, Label, label = generators(TheoryLabeledDDS)
V, E, s, t, Weight, weight = generators(TheoryWeightedGraph)

ldds = LabeledDDS{Int}()
add_parts!(ldds, :X, 4, Φ=[2,3,4,1], label=[100, 101, 102, 103])

wg = WeightedGraph{Int}(4)
add_parts!(wg, :E, 4, src=[1,2,3,4], tgt=[2,3,4,1], weight=[101, 102, 103, 100])

@test wg == migrate(WeightedGraph{Int}, ldds,
  Dict(:V => :X, :E => :X, :Weight => :Label),
  Dict(:src => id(S), :tgt => :Φ, :weight => [:Φ, :label]))

@test Presentation(Graph(1)) == TheoryGraph
@test Presentation(ldds) == TheoryLabeledDDS

F = FinFunctor(
  Dict(V => S, E => S, Weight => Label),
  Dict(s => id(S), t => ϕ, weight => compose(ϕ, label)),
  TheoryWeightedGraph, TheoryLabeledDDS
)
ΔF = DeltaMigration(F, LabeledDDS{Int}, WeightedGraph{Int})
@test wg == ΔF(ldds)

idF = FinFunctor(
  Dict(X => X, Label => Label), 
  Dict(ϕ => ϕ, label => label), 
  TheoryLabeledDDS, TheoryLabeledDDS
)
@test ldds == migrate(LabeledDDS{Int}, ldds, idF)

# Conjunctive migration
#######################

# Graph whose edges are paths of length 2.
V, E, src, tgt = generators(TheoryGraph)
C = FinCat(TheoryGraph)
F_V = FinDomFunctor([V], FinCat(1), C)
F_E = FinDomFunctor(FreeDiagram(Cospan(tgt, src)), C)
F = FinDomFunctor(Dict(V => Diagram{op}(F_V),
                       E => Diagram{op}(F_E)),
                  Dict(src => DiagramHom{op}([(1, src)], F_E, F_V),
                       tgt => DiagramHom{op}([(2, tgt)], F_E, F_V)), C)
@test F isa DataMigrations.ConjSchemaMigration
g = path_graph(Graph, 5)
H = migrate(g, F, tabular=true)
@test length(H(V)) == 5
@test length(H(E)) == 3
@test H(src)((x1=2, x2=3, x3=3)) == (x1=2,)
@test H(tgt)((x1=2, x2=3, x3=3)) == (x1=4,)

# Same query, but with `@migration` macro.
F = @migration TheoryGraph TheoryGraph begin
  V => V
  E => @join begin
    v::V
    (e₁, e₂)::E
    (t: e₁ → v)::tgt
    (s: e₂ → v)::src
  end
  src => e₁ ⋅ src
  tgt => e₂ ⋅ tgt
end
H = migrate(g, F, tabular=true)
@test length(H(V)) == 5
@test length(H(E)) == 3
@test H(src)((v=3, e₁=2, e₂=3)) == (V=2,)
@test H(tgt)((v=3, e₁=2, e₂=3)) == (V=4,)

h = migrate(Graph, g, F)
@test (nv(h), ne(h)) == (5, 3)
@test sort!(collect(zip(h[:src], h[:tgt]))) == [(1,3), (2,4), (3,5)]

h = Graph(5)
migrate!(h, g, F)
@test (nv(h), ne(h)) == (10, 3)
@test sort!(collect(zip(h[:src], h[:tgt]))) == [(6,8), (7,9), (8,10)]

# Graph whose vertices are paths of length 2 and edges are paths of length 3.
F = @migration TheoryGraph TheoryGraph begin
  V => @join begin
    v::V
    (e₁, e₂)::E
    (t: e₁ → v)::tgt
    (s: e₂ → v)::src
  end
  E => @join begin
    (v₁, v₂)::V
    (e₁, e₂, e₃)::E
    (t₁: e₁ → v₁)::tgt
    (s₁: e₂ → v₁)::src
    (t₂: e₂ → v₂)::tgt
    (s₂: e₃ → v₂)::src
  end
  src => (v => v₁; e₁ => e₁; e₂ => e₂; t => t₁; s => s₁)
  tgt => (v => v₂; e₁ => e₂; e₂ => e₃; t => t₂; s => s₂)
end
g = path_graph(Graph, 6)
h = migrate(Graph, g, F)
@test h == path_graph(Graph, 4)

# Agglomerative migration
#########################

# Free reflexive graph on a graph.
F = @migration TheoryReflexiveGraph TheoryGraph begin
  V => V
  E => @cases (v::V; e::E)
  src => (e => src)
  tgt => (e => tgt)
  refl => v
end
g = cycle_graph(Graph, 5)
h = migrate(ReflexiveGraph, g, F)
@test h == cycle_graph(ReflexiveGraph, 5)

# Free symmetric graph on a graph.
F = @migration TheorySymmetricGraph TheoryGraph begin
  V => V
  E => @cases (fwd::E; rev::E)
  src => (fwd => src; rev => tgt)
  tgt => (fwd => tgt; rev => src)
  inv => (fwd => rev; rev => fwd)
end
g = star_graph(Graph, 5)
h = migrate(SymmetricGraph, g, F)
@test is_isomorphic(h, star_graph(SymmetricGraph, 5))

# Sigma migration
#################

V1B, V2B, EB = generators(TheoryUndirectedBipartiteGraph, :Ob)
srcB, tgtB = generators(TheoryUndirectedBipartiteGraph, :Hom)

VG, EG = generators(TheoryGraph, :Ob)
srcG, tgtG = generators(TheoryGraph, :Hom)

F = FinFunctor(
  Dict(V1B => VG, V2B => VG, EB => EG),
  Dict(srcB => srcG, tgtB => tgtG),
  TheoryUndirectedBipartiteGraph, TheoryGraph
)

idF = FinFunctor(
  Dict(VG => VG, EG => EG),
  Dict(srcG => srcG, tgtG => tgtG),
  TheoryGraph, TheoryGraph
)

ΣF = SigmaMigration(F, UndirectedBipartiteGraph, Graph)
X = UndirectedBipartiteGraph()

Y = ΣF(X)
@test nparts(Y, :V) == 0
@test nparts(Y, :E) == 0

X = @acset UndirectedBipartiteGraph begin
  V₁ = 4
  V₂ = 3
  E = 4
  src = [1,2,2,3]
  tgt = [1,1,2,3]
end

Y = ΣF(X)
@test nparts(Y, :V) == 7
@test nparts(Y, :E) == 4
@test length(Y[:src] ∩ Y[:tgt]) == 0

@test SigmaMigration(idF, Graph, Graph)(Y) == Y

@present ThSpan(FreeSchema) begin
  (L1, L2, A)::Ob
  l1::Hom(A, L1)
  l2::Hom(A, L2)
end
@acset_type Span(ThSpan, index=[:l1, :l2])

X = @acset Span begin
  L1 = 3
  L2 = 4
  A = 3
  l1 = [1,1,2]
  l2 = [1,2,3]
end

@present ThInitial(FreeSchema) begin
  I::Ob
end
@acset_type Initial(ThInitial)

L1, L2, A = generators(ThSpan, :Ob)
l1, l2 = generators(ThSpan, :Hom)
I = generators(ThInitial)[1]

bang = FinFunctor(
  Dict(L1 => I, L2 => I, A => I),
  Dict(l1 => id(I), l2 => id(I)),
  ThSpan, ThInitial
)

Σbang = SigmaMigration(bang, Span, Initial)
Y = Σbang(X)

@test nparts(Y, :I) == 4

vertex = FinFunctor(Dict(I => VG), Dict(), ThInitial, TheoryGraph)
edge = FinFunctor(Dict(I => EG), Dict(), ThInitial, TheoryGraph)

Z = SigmaMigration(vertex, Initial, Graph)(Y)
@test nparts(Z, :V) == 4
@test nparts(Z, :E) == 0

Z = SigmaMigration(edge, Initial, Graph)(Y)
@test nparts(Z, :V) == 8
@test nparts(Z, :E) == 4
@test Z[:src] ∪ Z[:tgt] == 1:8

end
