# DandelionWebSockets
DandelionWebSockets is a client side WebSocket package.

## Preparation tasks
What needs to be done before this is registered as a package?

- Documentation:
    + Design
    + Usage
    + Code
- Refine the public interface.
- Missing state callbacks (open, connecting).
- Sending ping frames, ensuring we get a reply.
- Improve error handling.
- Set version (use semantic versioning?)

Completed preparation tasks:

- Rename to DandelionWebSockets.
- Use the BufferedStreams package instead of our own TLSBufferedIO, if possible.
- Wait for Requests.jl to make a release with the HTTP upgrade feature.
    + Update REQUIRE to reflect the new version of Requests.jl.


## Usage
