""" Draw wiring diagrams (aka string diagrams) in various formats.
"""
module TikZWiring
export WiresTikZ, PortTikZ, BoxTikZ, BoxSpec, wiring_diagram, wires, box,
  sequence, parallel, rect, trapezium, lines, cross_wires

import Formatting: format

import ...Doctrine: ObExpr, HomExpr, dom, codom, head, args, compose, id
import ..TikZ

# Data types
############

""" Object in a TikZ wiring diagram.
"""
typealias WiresTikZ Vector{String}

immutable PortTikZ
  label::String
  anchor::String
  angle::Int
  show_label::Bool
  PortTikZ(label::String, anchor::String; angle::Int=0, show_label::Bool=true) =
    new(label, anchor, angle, show_label)
end

""" Morphism in a TikZ wiring diagram.
"""
immutable BoxTikZ
  node::TikZ.Node
  inputs::Vector{PortTikZ}
  outputs::Vector{PortTikZ}
end
dom(box::BoxTikZ)::WiresTikZ = [ port.label for port in box.inputs ]
codom(box::BoxTikZ)::WiresTikZ  = [ port.label for port in box.outputs ]

""" Specification for a box (morphism) in a TikZ wiring diagram.
"""
immutable BoxSpec
  name::String
  style::Dict
end

# Wiring diagrams
#################

""" Draw a wiring diagram in TikZ for the given morphism expression.

The diagram is constructed recursively, mirroring the structure of the formula.
This is achieved by nesting TikZ pictures in TikZ nodes recursively--a feature
not officially supported by TikZ but that is nonetheless in widespread use.

Warning: Since our implementation uses the `remember picture` option, LaTeX must
be run at least *twice* to fully render the picture. See (TikZ Manual,
Sec 17.13).
"""
function wiring_diagram(f::HomExpr;
    font_size::Number=12, line_width::String="0.4pt", math_mode::Bool=true,
    arrowtip::String="", labels::Bool=true,
    box_padding::String="0.333em", box_size::Number=2,
    sequence_sep::Number=2, parallel_sep::Number=0.5)::TikZ.Picture
  # Parse arguments.
  style = Dict(:arrowtip => !isempty(arrowtip), :labels => labels,
               :box_padding => box_padding, :box_size => box_size,
               :sequence_sep => sequence_sep, :parallel_sep => parallel_sep)
  spec = BoxSpec("n", style)
  
  # Draw input and output arrows by adding identities on either side of f. 
  f_ext = f
  if head(f) == :id
    f_ext = compose(id(dom(f)), f_ext)
  else
    if head(dom(f)) != :munit
      f_ext = compose(id(dom(f)), f_ext)
    end
    if head(codom(f)) != :munit
      f_ext = compose(f_ext, id(codom(f)))
    end
  end
  
  # Create node for extended morphism.
  box_tikz = box(f_ext, spec)
  
  # Create picture with this single node.
  props = [
    TikZ.Property("remember picture"),
    TikZ.Property("font", 
                  "{\\fontsize{$(format(font_size))}{$(format(1.2*font_size))}}"),
    TikZ.Property("container/.style", "{inner sep=0}"),
    TikZ.Property("every path/.style",
                  "{solid, line width=$line_width}"),
  ]
  if !isempty(arrowtip)
    decoration = "{markings, mark=at position 0.5 with {\\arrow{$arrowtip}}}"
    push!(props, TikZ.Property("decoration", decoration))
  end
  if math_mode
    append!(props, [ TikZ.Property("execute at begin node", "\$"),
                     TikZ.Property("execute at end node", "\$") ])
  end
  TikZ.Picture(box_tikz.node; props=props)
end

""" Create wires for an object expression.
"""
function wires(A::ObExpr)::WiresTikZ end

""" Create box for a morphism expression.
"""
function box(f::HomExpr, spec::BoxSpec)::BoxTikZ end

function subbox(f::HomExpr, spec::BoxSpec, n::Int)::BoxTikZ
  box(f, BoxSpec("$(spec.name)$n", spec.style))
end

# Defaults
##########

# These methods are reasonable to define for the base expression types since
# they will rarely be changed.

wires(A::ObExpr{:generator}) = [ string(first(A)) ]
wires(A::ObExpr{:munit}) = []
wires(A::ObExpr{:otimes}) = vcat(map(wires, args(A))...)

box(f::HomExpr{:id}, spec::BoxSpec) = lines(wires(dom(f)), spec)
box(f::HomExpr{:compose}, spec::BoxSpec) = sequence(args(f), spec)
box(f::HomExpr{:otimes}, spec::BoxSpec) = parallel(args(f), spec)
box(f::HomExpr{:braid}, spec::BoxSpec) = cross_wires(wires(dom(f)), spec)

""" Default renderers for specific syntaxes.
"""
module Defaults
  export box, wires
  
  using ..TikZWiring
  import ..TikZWiring: box, wires
  using CompCat.Doctrine
  
  # Category
  box(f::FreeCategory.Hom{:generator}, spec::BoxSpec) = rect(f, spec)

  # Symmetric monoidal category
  box(f::FreeSymmetricMonoidalCategory.Hom{:generator}, spec::BoxSpec) = rect(f, spec)

  # (Co)cartesian category
  box(f::FreeCartesianCategory.Hom{:generator}, spec::BoxSpec) = rect(f, spec)
  box(f::FreeCartesianCategory.Hom{:mcopy}, spec::BoxSpec) = 
    split_wires(wires(dom(f)), spec)
  box(f::FreeCartesianCategory.Hom{:delete}, spec::BoxSpec) =
    delete_wires(wires(dom(f)), spec)  
  
  box(f::FreeCocartesianCategory.Hom{:generator}, spec::BoxSpec) = rect(f, spec)
  box(f::FreeCocartesianCategory.Hom{:mmerge}, spec::BoxSpec) =
    merge_wires(wires(codom(f)), spec)
  box(f::FreeCocartesianCategory.Hom{:create}, spec::BoxSpec) =
    create_wires(wires(codom(f)), spec)
end

# Elements of wiring diagrams
#############################

""" A rectangle, the default style for generators.
"""
function rect(content::String, dom::WiresTikZ, codom::WiresTikZ, spec::BoxSpec;
              padding::String="", rounded::Bool=true)::BoxTikZ
  name, style = spec.name, spec.style
  dom_ports = box_anchors(dom, name, style, dir="west", angle=180)
  codom_ports = box_anchors(codom, name, style, dir="east", angle=0)
  size = box_size(max(length(dom_ports), length(codom_ports)), style)
  
  padding = isempty(padding) ? spec.style[:box_padding] : padding
  props = [
    TikZ.Property("draw"),
    TikZ.Property("solid"),
    TikZ.Property("inner sep", padding),
    TikZ.Property("rectangle"),
    TikZ.Property(rounded ? "rounded corners" : "sharp corners"),
    TikZ.Property("minimum height", "$(size)em"),
  ]
  node = TikZ.Node(name; content=content, props=props)
  BoxTikZ(node, dom_ports, codom_ports)
end
function rect(f::HomExpr{:generator}, spec::BoxSpec; kw...)::BoxTikZ
  rect(string(first(f)), wires(dom(f)), wires(codom(f)), spec; kw...)
end

""" A trapezium node, the default style for generators in dagger categories.

The node content is a nested TikZ picture that contains a single visible node.
Nesting pictures even at this level may seem crazy, but it's the only way I know
to get a bounding box on the inner node, regardless of its shape, *before* it's
rendered.
"""
function trapezium(content::String, dom::WiresTikZ, codom::WiresTikZ, spec::BoxSpec;
                   padding::String="", rounded::Bool=true,
                   angle::Int=80, reverse::Bool=false)::BoxTikZ
  name, style = spec.name, spec.style
  dom_ports = box_anchors(dom, name, style, dir="west", angle=180)
  codom_ports = box_anchors(codom, name, style, dir="east", angle=0)
  size = box_size(max(length(dom_ports), length(codom_ports)), style)
  
  padding = isempty(padding) ? spec.style[:box_padding] : padding
  props = [
    TikZ.Property("draw"),
    TikZ.Property("solid"),
    TikZ.Property("inner sep", padding),
    TikZ.Property("trapezium"),
    TikZ.Property("trapezium angle", "$angle"),
    TikZ.Property("trapezium stretches body"),
    TikZ.Property("shape border rotate", reverse ? "90" : "270"),
    TikZ.Property(rounded ? "rounded corners" : "sharp corners"),
    # Actually the height because of rotation.
    TikZ.Property("minimum width", "$(size)em"),
  ]
  node = TikZ.Node("$name box"; content=content, props=props)
  picture = TikZ.Picture(node)
  
  props = [ TikZ.Property("container") ]
  node = TikZ.Node(name; content=picture, props=props)
  BoxTikZ(node, dom_ports, codom_ports)
end
function trapezium(f::HomExpr{:generator}, spec::BoxSpec; kw...)::BoxTikZ
  trapezium(string(first(f)), wires(dom(f)), wires(codom(f)), spec; kw...)
end

""" Straight lines, used to draw identity morphisms.
"""
function lines(wires::WiresTikZ, spec::BoxSpec)::BoxTikZ
  name, style = spec.name, spec.style
  dom_ports = box_anchors(wires, name, style, dir="center", angle=180)
  codom_ports = box_anchors(wires, name, style, dir="center", angle=0)
  height = box_size(length(wires), style)
  props = [ TikZ.Property("minimum height", "$(height)em") ]
  node = TikZ.Node(name; props=props)
  BoxTikZ(node, dom_ports, codom_ports)
end

""" Boxes in sequence, used to draw compositions.
"""
function sequence(homs::Vector, spec::BoxSpec)::BoxTikZ
  name, style = spec.name, spec.style
  sequence_sep = style[:sequence_sep]
  edge_props = style[:arrowtip] ?
    [ TikZ.Property("postaction", "{decorate}") ] : []
  edge_node_props = [
    TikZ.Property("above", "0.25em"),
    TikZ.Property("midway")
  ]
  
  mors = [ subbox(g, spec, i) for (i,g) in enumerate(homs) ]
  stmts = TikZ.Statement[ mors[1].node ]
  for i = 2:length(mors)
    push!(mors[i].node.props,
          TikZ.Property("right=$(sequence_sep)em of $name$(i-1))"))
    push!(stmts, mors[i].node)
    for j = 1:length(mors[i].inputs)
      src_port = mors[i-1].outputs[j]
      tgt_port = mors[i].inputs[j]
      
      # Create edge node for label.
      if (style[:labels] && src_port.show_label && tgt_port.show_label)
        content = tgt_port.label # == src_port.label
        node = TikZ.EdgeNode(content=content, props=edge_node_props)
      else
        node = Nullable()
      end
      
      # Create path operation and draw edge.
      op = TikZ.PathOperation("to"; props=[
        TikZ.Property("out", string(src_port.angle)),
        TikZ.Property("in", string(tgt_port.angle)),
      ])
      edge = TikZ.Edge(src_port.anchor, tgt_port.anchor;
                       op=op, props=edge_props, node=node)
      push!(stmts, edge)
    end
  end

  props = [ TikZ.Property("container") ]
  node = TikZ.Node(name; content=TikZ.Picture(stmts...), props=props)
  BoxTikZ(node, first(mors).inputs, last(mors).outputs)
end

""" Boxes in parallel, used to draw monoidal products.
"""
function parallel(homs::Vector, spec::BoxSpec)::BoxTikZ
  name, style = spec.name, spec.style
  parallel_sep = style[:parallel_sep]
  
  mors = []
  for (i,g) in enumerate(homs)
    mor = subbox(g, spec, i)
    if i > 1
      push!(mor.node.props,
            TikZ.Property("below=$(parallel_sep)em of $name$(i-1)"))
    end
    push!(mors, mor)
  end
  stmts = TikZ.Statement[ mor.node for mor in mors ]

  props = [ TikZ.Property("container") ]
  node = TikZ.Node(name; content=TikZ.Picture(stmts...), props=props)
  inputs = vcat([ mor.inputs for mor in mors]...)
  outputs = vcat([ mor.outputs for mor in mors]...)
  BoxTikZ(node, inputs, outputs)
end

function cross_wires(wires::WiresTikZ, spec::BoxSpec)
  @assert length(wires) == 2
  A, B = wires[1], wires[2]
  name, style = spec.name, spec.style
  center = "$name.center"
  dom = [ PortTikZ(A, center, angle=135), PortTikZ(B, center, angle=225) ]
  codom = [ PortTikZ(B, center, angle=45), PortTikZ(A, center, angle=315) ]
  props = [
    TikZ.Property("minimum height", "$(box_size(2,style))em")
  ]
  node = TikZ.Node(name; props=props)
  BoxTikZ(node, dom, codom)
end

function split_wires(wires::WiresTikZ, spec::BoxSpec)
  @assert length(wires) == 1
  A = wires[1]
  name, style = spec.name, spec.style
  dom = [ PortTikZ(A, "$name point.west", angle=180) ]
  codom = [ PortTikZ(A, "$name point.north", angle=90, label=false),
            PortTikZ(A, "$name point.south", angle=270, label=false) ]
  node = monoid_node_tikz(name, style, 2)
  BoxTikZ(node, dom, codom)
end

function merge_wires(wires::WiresTikZ, spec::BoxSpec)
  @assert length(wires) == 1
  A = wires[1]
  name, style = spec.name, spec.style
  dom = [ PortTikZ(A, "$name point.north", angle=90, label=false),
          PortTikZ(A, "$name point.south", angle=270, label=false) ]
  codom = [ PortTikZ(A, "$name point.east", angle=0) ]
  node = monoid_node_tikz(name, style, 2)
  BoxTikZ(node, dom, codom)
end

function create_wires(wires::WiresTikZ, spec::BoxSpec)
  @assert length(wires) == 1
  name, style = spec.name, spec.style
  ports = [ PortTikZ(wires[1], "$name point.east", angle=0) ]
  node = monoid_node_tikz(name, style, 1)
  BoxTikZ(node, [], ports)
end

function delete_wires(wires::WiresTikZ, spec::BoxSpec)
  @assert length(wires) == 1
  name, style = spec.name, spec.style
  ports = [ PortTikZ(wires[1], "$name point.west", angle=180) ]
  node = monoid_node_tikz(name, style, 1)
  BoxTikZ(node, ports, [])
end

function cup(wires::WiresTikZ, spec::BoxSpec)
  @assert length(wires) == 2
  name, style = spec.name, spec.style
  ports = [ PortTikZ(wires[1], "$name.center", angle=90, label=false),
            PortTikZ(wires[2], "$name.center", angle=270, label=false) ]
  props = [
    TikZ.Property("minimum height", "$(box_size(2,style))em")
  ]
  node = TikZ.Node(name; props=props)
  BoxTikZ(node, ports, [])
end

function cap(wires::WiresTikZ, spec::BoxSpec)
  @assert length(wires) == 2
  name, style = spec.name, spec.style
  ports = [ PortTikZ(wires[1], "$name.center", angle=90, label=false),
            PortTikZ(wires[2], "$name.center", angle=270, label=false) ]
  props = [
    TikZ.Property("minimum height", "$(box_size(2,style))em")
  ]
  node = TikZ.Node(name; props=props)
  BoxTikZ(node, [], ports)
end

""" Create a TikZ node for a (co)monoid morphism.

Uses a small, visible node for the point and a big, invisible node as a spacer.
FIXME: Is there a more elegant way to achieve the desired margin?
"""
function monoid_node_tikz(name::String, style::Dict, ports::Int)::TikZ.Node
  pic = TikZ.Picture(
    TikZ.Node("$name box"; props=[
      TikZ.Property("minimum height", "$(box_size(ports,style))em"),
    ]),
    TikZ.Node("$name point"; props=[
      TikZ.Property("draw"),
      TikZ.Property("fill"),
      TikZ.Property("circle"),
      TikZ.Property("minimum size", "0.333em"),
      TikZ.Property("above", "0 of $name box.center"),
      TikZ.Property("anchor", "center"),
    ]),
  )
  TikZ.Node(name; content=pic, props=[TikZ.Property("container")])
end

# Helper functions
##################

""" Compute the size of a box from the number of its ports.

We use the unique formula consistent with the monoidal product, meaning that
the size of a product of generator boxes depends only on the total number of
ports, not the number of generators.
"""
function box_size(ports::Int, style::Dict)::Number
  m = max(1, ports)
  m * style[:box_size] + (m-1) * style[:parallel_sep]
end

""" Compute the locations of ports on a box.

These anchors are consistent with the monoidal product (see `box_size`).
"""
function box_anchors(wires::WiresTikZ, name::String, style::Dict;
                     dir::String="center", kwargs...)::Vector{PortTikZ}
  box_size, parallel_sep = style[:box_size], style[:parallel_sep]
  m = length(wires)
  if m == 0
    return []
  elseif m == 1
    return [ PortTikZ(wires[1], "$name.$dir"; kwargs...) ]
  end
  
  result = []
  start = (m*box_size + (m-1)*parallel_sep) / 2
  for (i,label) in enumerate(wires)
    offset = box_size/2 + (i-1)*(box_size+parallel_sep)
    anchor = "\$($name.$dir)+(0,$(start-offset)em)\$"
    push!(result, PortTikZ(label, anchor; kwargs...))
  end
  return result
end

end