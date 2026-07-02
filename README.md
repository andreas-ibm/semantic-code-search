# Semantic Code Searcher
## Requirements
... This will add enteries into the elastic index which will be inputed into a queory engine, from there, the engine will connect to the database to provide results for the user.
## Architecture
You have a set of code that needs indexing, which requires an ingestion tool. To achieve this, you will need to use the semantic code search indexer to fill the database. After that, the query engine can connect to the database using either the MCP or HTTP server to provide results to the user. This process can take place through an AI coding tool or directly to the user, via the servers.
## Steps
First the code goes through the ingestion tool, making AI and search engines able to understand it, then it gets to the elastic database where a query engine queries it to interpret the request and gather necessary data for it. It then can go to either the AI or the user, requested with or to the web.
