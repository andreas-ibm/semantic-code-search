# Semantic Code Searcher


## Requirements
We need a system that can provide search results from our codebase that aren't a perfect match to our search term. 
### Minimum
- Semantic Search
- Index large codebases
- Multiple source codebases
- MCP API
- Containerised
- Language support:
  - C++
  - Java
  - Javascript
 
### Additional desired features
- [ ] Web UI
- [ ] Lanuage support:
  - [ ] Python
  - [ ] Bash
  - [ ] PL/1
  - [ ] Rust
  - [ ] Perl
- [ ] Scheduled indexing
- [ ] Triggered indexing


## Architecture
You have a set of code that needs indexing, which requires an ingestion tool. To achieve this, you will need to use the semantic code search indexer to fill the database. After that, the query engine can connect to the database using either the MCP or HTTP server to provide results to the user. This process can take place through an AI coding tool or directly to the user, via the servers.


## Manual steps
first the code goes through the ingestion tool, making ai and search engines able to understand it, then it gets to the elastic database, then a query engine querys it to interpret the request and gather necessary data for it, it then can go to either the ai the user requested with or to the web.

