func fixtureNonisolatedImplicit() async {
  await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in c.resume() }
}
func fixtureNonisolatedExplicit() async {
  await withCheckedContinuation(isolation: #isolation) { (c: CheckedContinuation<Void, Never>) in c.resume() }
}
actor FixtureActor {
  func fixtureActorImplicit() async {
    await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in c.resume() }
  }
  func fixtureActorExplicit() async {
    await withCheckedContinuation(isolation: #isolation) { (c: CheckedContinuation<Void, Never>) in c.resume() }
  }
}
@MainActor func fixtureMainActorImplicit() async {
  await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in c.resume() }
}
@MainActor func fixtureMainActorExplicit() async {
  await withCheckedContinuation(isolation: #isolation) { (c: CheckedContinuation<Void, Never>) in c.resume() }
}
