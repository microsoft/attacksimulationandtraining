# Attack Simulation and Training

Welcome to the Attack Simulation and Training repro:

Here you will find some samples, scripts, tools and other pieces of information that we feel as a product group
will help you get the most out of our feature Attack Simulation and Training.

2 Scripts in this location are:
AST Write  Batch PS5
AST Write Hunting PS5

Both required PS v5 to run.
You will need to register an Azure App in your tenant, graning Attacksim Admin, User Read and Threat Hunting permissions.

## DO NOT USE IN PRODUCTION ENVIRONMENTS, THESE ARE DEMONSTRATION SCRIPTS WITH LIMITED ERROR CHECKING. 
The batch script as is, will send a simulation to **ALL** users in your environment unless you edit the target scope.

### AST Write  Batch PS5
Auths against our api app registration.
Gets all global payloads that are of type cred harvest.
Gets all users from AD and randomizes list.
Splits users into chunks (configurable)
Grabs a random payload, removes from pool
Sends simulations in chunks based on split

### AST Write Hunting PS5
Auths against our api app registration.
Gets all global payloads that are of type cred harvest.
Gets top targeted users for phish from advanced hunting.
Sends simulation to top targeted users.



