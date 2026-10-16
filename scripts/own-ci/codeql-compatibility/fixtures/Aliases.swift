func fixtureClassIdentity(_ value: Collision) -> Collision { value }
func fixtureProtocolIdentity(_ value: any CollisionProtocol) -> any CollisionProtocol { value }
func fixtureAliases() {
  _ = FixtureNumberAlias
  _ = FixtureGlobalAlias
  _ = FixtureFunctionAlias(7)
}
