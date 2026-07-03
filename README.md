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

```mermaid
graph TB
    %% Out of scope components (gray)
    User[User]:::outOfScope
    Browser[Browser]:::outOfScope
    AIAgent[AI Agent<br/>e.g. Bob]:::outOfScope
    GitRepos[Git Repositories]:::outOfScope
    
    %% Project components
    MCPServer[MCP Server<br/>Container]:::projectComponent
    HTTPServer[HTTP Server<br/>Container]:::projectComponent
    QueryEngine[Query Engine]:::projectComponent
    IndexDB[(Index Database)]:::projectComponent
    ElasticContainer[Elastic Container]:::container
    CodeIngestion[Code Ingestion Tool]:::projectComponent
    
    %% User interactions
    User -->|uses| AIAgent
    User -->|uses| Browser
    
    %% AI and Browser connections
    AIAgent -->|connects to| MCPServer
    Browser -->|connects to| HTTPServer
    
    %% Server to Query Engine
    MCPServer -->|queries| QueryEngine
    HTTPServer -->|queries| QueryEngine
    
    %% Query Engine to Database
    QueryEngine -->|reads from| IndexDB
    
    %% Container grouping
    subgraph ElasticContainer[Elastic Container]
        QueryEngine
        IndexDB
    end
    
    %% Ingestion flow (separate)
    GitRepos -.->|reads| CodeIngestion
    CodeIngestion -.->|populates| IndexDB
    
    %% Styling
    classDef outOfScope fill:#e0e0e0,stroke:#999,stroke-width:2px,color:#333
    classDef projectComponent fill:#4a90e2,stroke:#2e5c8a,stroke-width:2px,color:#fff
    classDef container fill:#f0f0f0,stroke:#666,stroke-width:3px,stroke-dasharray: 5 5
    
    style ElasticContainer fill:#fff9e6,stroke:#ff9800,stroke-width:3px
```

You have a set of code that needs indexing, which requires an ingestion tool. To achieve this, you will need to use the semantic code search indexer to fill the database. After that, the query engine can connect to the database using either the MCP or HTTP server to provide results to the user. This process can take place through an AI coding tool or directly to the user, via the servers.


## Manual steps
first the code goes through the ingestion tool, making ai and search engines able to understand it, then it gets to the elastic database, then a query engine querys it to interpret the request and gather necessary data for it, it then can go to either the ai the user requested with or to the web.

