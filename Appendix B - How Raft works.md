# Appendix B - How Raft works.md

The Raft consensus algorithm's leader election process is crucial for ensuring that a distributed system can continue to operate even when some of its nodes fail. 

## Key Concepts:

* **Terms**: Raft divides time into "terms," 
  * Terms have numbers that increase monotonically
  *  Each term starts with an election
  *  One or more candidates attempting to become leader
  *  Winning candidate (if any) serves as leader for the rest of the term
  *  Terms allow detection of stale information
  *  Each server stores current term
  *  Checked on every request
  *  Different servers observe term transitions differently
* **Request-response protocol** between servers (remote procedure calls, or RPCs). 2 request types:
     * `RequestVote`
     * `AppendEntries` (also serves as heartbeat)
* **Heartbeats**: The leader sends periodic "heartbeat" messages to followers to maintain its authority.
* **Roles**:
      * **Leader**: Responsible for handling client requests and replicating logs.
      * **Follower**: Passively accepts logs and heartbeats from the leader.
      * **Candidate**: Initiates an election to become the leader.
* **Election Timeout**: If a follower doesn't receive a heartbeat within a certain timeout period, it becomes a candidate.
* **Votes**: Candidates request votes from other nodes. A candidate becomes a leader if it receives votes from a majority of the nodes.
* **Log Recency**: Raft ensures that the leader with the most up-to-date log is elected.




## How the Leader Election Works:

### Timeout:
Followers have randomized election timeouts, different for each node. 
This helps to prevent multiple nodes from becoming candidates simultaneously.
If a follower's election timeout expires, it transitions to the candidate state.

### Requesting Votes:
The candidate increments its current term and votes for itself.
It then sends `RequestVote` RPCs to all other nodes in the cluster.

### Voting:
A node votes for a candidate if:
* The candidate's term is at least as high as its own (the election could be referred to an older term).
* The node has not already voted for another candidate in that term.
* The candidates log is at least as up to date as the voters log.


### Becoming Leader:
If a candidate receives votes from a majority of the nodes, it becomes the leader.
The new leader then sends heartbeat messages to all followers to establish its authority.

## Example:

Imagine a Raft cluster with 5 nodes (A, B, C, D, and E).

### Leader Failure:
The current leader (let's say it's A) fails.
Followers B, C, D, and E eventually time out because they stop receiving heartbeats.

### Candidate State:
Nodes B and D(For this example) become candidates.
They both increment their terms and send `RequestVote` RPCs to the other nodes.

### Voting:
Assume that node D's log is more up-to-date than node B's.
Nodes C and E receive the `RequestVote` RPCs. 
Because node D's log is more up to date, they vote for node D. 
Node D also votes for itself. Node B receives some votes, but not a majority.

### Leader Election:
Node D receives a majority of votes (3 out of 5) and becomes the new leader.
Node D then starts sending heartbeat messages to B, C, and E.


## Log Replication
* Handled by leader
* Log entries: index, term, command
* When client request arrives:
      * Append to local log
  * Replicate to other servers using `AppendEntries` requests
  * **Committed**: entry replicated by leader to majority of servers
  * Once committed, apply to local state machine
  * Return result to client
  * Notify other servers of committed entries in future AppendEntries requests
* Logs can become inconsistent after leader crashes
* Raft maintains a high level of coherency between logs (Log Matching Property):
  * If entries in different logs have same term and index, then
    * They also have the same command
    * The two logs are identical up through that entry
* `AppendEntries` consistency check preserves above properties.
    * Leader forces other logs to match its own:
    * `nextIndex` for each follower (initialized to leader's log length)
    * If `AppendEntries` fails, reduce `nextIndex` for that follower and retry.
    * If follower receives conflicting entries but consistency check passes, removes all conflicting entries