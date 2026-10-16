import swift
import codeql.swift.generated.ParentChild

private Element child(Element parent) { result = getImmediateChild(parent, _) }

private string declName(Decl declaration) {
  result = declaration.(VarDecl).getName()
  or result = declaration.(Function).getName()
  or result = declaration.(EnumElementDecl).getName()
}

private string actorKind(Expr actor) {
  actor instanceof NilLiteralExpr and result = "nil"
  or
  exists(DeclRefExpr reference |
    reference = child*(actor) and declName(reference.getDecl()) = "self" and result = "self"
  )
  or
  exists(MemberRefExpr reference |
    reference = child*(actor) and declName(reference.getMember()) = "shared" and result = "shared"
  )
}

from string category, string owner, string value
where
  exists(CurrentContextIsolationExpr isolation |
    (
      owner = isolation.getEnclosingFunction().getShortName()
      or
      exists(DefaultArgumentExpr argument |
        argument.getCallerSideDefault() = isolation and
        argument.getParamDecl().getName() = "isolation" and
        owner = argument.getEnclosingFunction().getShortName()
      )
    ) and owner.matches("fixture%") and
    category = "isolation" and value = actorKind(isolation.getActor())
  )
  or
  exists(DeclRefExpr reference |
    reference.getEnclosingFunction().getShortName() = "fixtureAliases" and
    category = "alias-reference" and owner = "fixtureAliases" and value = declName(reference.getDecl())
  )
  or
  exists(ClassDecl declaration |
    declaration.getName() = "Collision" and category = "class" and owner = "Collision" and value = "present"
  )
  or
  exists(ProtocolDecl declaration |
    declaration.getName() = "CollisionProtocol" and category = "protocol" and owner = "CollisionProtocol" and value = "present"
  )
  or
  exists(DefaultArgumentExpr argument |
    owner = argument.getEnclosingFunction().getShortName() and owner.matches("fixture%") and
    argument.getParamDecl().getName() = "isolation" and
    category = "caller-default" and value = argument.getCallerSideDefault().getAPrimaryQlClass()
  )
select category, owner, value
