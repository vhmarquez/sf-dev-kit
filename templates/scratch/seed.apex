// sf-dev-kit/scratch-org seed.apex
// Invoked by /sf-dev-kit:scratch-org create after deploy.
//
// Convention: define a public static `seed()` method on TestDataFactory that
// inserts a representative dataset. The factory class should be `@isTest`-
// annotated only if it must not deploy to production — for scratch orgs,
// either deploy a non-test variant (e.g., DevDataFactory) or temporarily
// remove the @isTest annotation in scratches.
//
// If the factory has no seed() method, this script no-ops with a message.

try {
    TestDataFactory.seed();
    System.debug(LoggingLevel.INFO, '[sf-dev-kit] TestDataFactory.seed() completed.');
} catch (NoSuchMethodException nme) {
    System.debug(LoggingLevel.WARN, '[sf-dev-kit] TestDataFactory.seed() not found. Define one to enable scratch-org seeding.');
} catch (Exception e) {
    System.debug(LoggingLevel.ERROR, '[sf-dev-kit] Seed failed: ' + e.getMessage() + '\n' + e.getStackTraceString());
    throw e;
}
