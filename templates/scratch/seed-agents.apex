// argo/scratch-org seed-agents.apex
// Invoked by /argo:scratch-org create after deploy when an agent is in the project.
//
// Convention: define a public static `seedAgents()` method on TestDataFactory
// that creates representative test data for agent eval runs (Cases, Orders,
// Contacts the agent will read/write during evals). If no method exists, this
// script no-ops with an informational message.
//
// This complements seed.apex (which seeds general test data); split because
// agent eval data is often larger, more structured, and project-specific.

try {
    TestDataFactory.seedAgents();
    System.debug(LoggingLevel.INFO, '[argo] TestDataFactory.seedAgents() completed.');
} catch (NoSuchMethodException nme) {
    System.debug(LoggingLevel.WARN, '[argo] TestDataFactory.seedAgents() not found. Define one if your project ships agents.');
} catch (Exception e) {
    System.debug(LoggingLevel.ERROR, '[argo] Agent seed failed: ' + e.getMessage() + '\n' + e.getStackTraceString());
    throw e;
}
