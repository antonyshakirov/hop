@protocol Collision
@end
__attribute__((objc_root_class)) @interface Collision
@end
#define CollisionAlias Collision

enum { FixtureNumber = 7 };
#define FixtureNumberAlias FixtureNumber
extern int fixtureGlobal;
#define FixtureGlobalAlias fixtureGlobal
extern int fixtureFunction(int value);
#define FixtureFunctionAlias fixtureFunction
