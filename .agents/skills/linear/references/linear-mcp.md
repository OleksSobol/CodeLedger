# Linear MCP Reference Guide

This reference outlines common operations with the Linear MCP server (`linear-mcp-server`).

## Key Tools & Signatures

### 1. `get_issue`
Retrieve issue details by identifier or UUID.
- **Parameters**:
  - `id` (string, required): e.g. `"CL-123"`, `"LIN-456"`.
  - `fields` (array of strings, optional):
    ```json
    ["id", "title", "description", "status", "priority", "labels", "gitBranchName", "assignee", "url", "attachments"]
    ```
  - `includeRelations` (boolean, optional): Include blocking/related issues.

### 2. `list_comments`
Retrieve discussion threads and inline comments on an issue.
- **Parameters**:
  - `issueId` (string, required): Issue identifier (e.g. `"CL-123"`).
  - `orderBy` (string, optional): `"createdAt"` or `"updatedAt"`.
  - `limit` (number, optional): Default `50`.

### 3. `save_issue`
Create or update an issue.
- **To update an existing issue**:
  - `id` (string, required): e.g. `"CL-123"`.
  - `state` (string, optional): Target state name or ID (e.g. `"In Progress"`, `"Done"`).
  - `assignee` (string, optional): User ID, email, name, or `"me"`.
  - `patch` / `description` (optional): Updates to the issue body.

### 4. `save_comment`
Post a comment to an issue thread.
- **Parameters**:
  - `issueId` (string, required): Issue identifier.
  - `body` (string, required): Markdown text of comment.

### 5. `extract_images`
Extract and inspect images referenced in issue description or comments.
- **Parameters**:
  - `markdown` (string, required): The markdown string containing image links.

