# PowerClaw — Question Bank

A reference of prompts to explore what PowerClaw can do with its current 13 tools.

---

## System Health & Performance

### Get-SystemSummary / Get-TopProcesses
- "Give me a full system health snapshot"
- "Is my machine under heavy load right now?"
- "What's eating all my CPU?"
- "How much RAM am I using and what's consuming the most?"
- "When did my machine last reboot?"
- "What are the top 10 processes by memory right now?"
- "Is anything using an unusual amount of resources?"
- "How many logical CPU cores does this machine have?"
- "What's my current page file usage?"
- "Am I close to running out of RAM?"
- "Which process has been running the longest?"
- "Show me everything using more than 500MB of memory"
- "Is Chrome or any browser taking up too much memory?"
- "What's my CPU load percentage right now?"

---

## Storage & Files

### Get-StorageStatus
- "How full are my drives?"
- "Which drive is closest to running out of space?"
- "What's taking up the most space in my Documents folder?"
- "How much free space do I have on C:?"
- "Give me a storage breakdown across all drives"
- "Which folder in my user profile is the biggest?"

### Search-Files
- "Find the 10 biggest files on my system"
- "How much video content do I have?"
- "How much music is on my system?"
- "How many pictures do I have and how much space are they taking?"
- "Find all zip files over 100MB"
- "Find all log files over 50MB"
- "What files have I modified today?"
- "Find all PowerShell scripts I've written in the last 30 days"
- "What's the single biggest file on my system?"
- "Find any duplicate-looking files in my Downloads folder"
- "How much disk space are my Downloads taking up in total?"
- "Find all .exe files I've downloaded in the last 90 days"
- "How many documents do I have?"
- "Find any files I haven't opened in over a year"
- "What did I download last week?"
- "Find all PDF files in my Documents"
- "How much space would I free up by deleting all zip files in Downloads?"
- "Find all files larger than 1GB anywhere in my user profile"
- "What are the most recently modified files in my projects folder?"
- "Find all config files across my PowerClaw project"

### Get-DirectoryListing
- "What's in my Downloads folder?"
- "Show me the contents of my PowerClaw tools directory"
- "List all the files in my Documents folder"
- "What PowerShell scripts are in my home directory?"
- "Show me everything in C:\Users\user\PowerClaw"
- "What's in my Desktop folder?"

### Read-FileContent
- "Read my PowerClaw config.json and explain my current settings"
- "Read my trading journal from last week and summarize what I was watching"
- "What does my PowerShell profile do?"
- "Read the README in my Downloads folder and tell me what this project is"
- "Read my PowerClaw log and tell me which tools I've used most"
- "What's in my .myjo config file?"
- "Read this error log and tell me what went wrong"
- "Summarize the last 50 lines of my PowerClaw log"
- "Read my tools-manifest.json and tell me what tools are approved"
- "What does Get-SystemSummary.ps1 actually do?"

### Remove-Files
- "Find duplicate rekordbox zip files in my Downloads and delete the older one"
- "Delete all zip files in my Downloads folder older than 6 months"
- "Clean up the log files in my PowerClaw folder"
- "Find all files over 500MB in Downloads that I haven't opened in a year and delete them"

---

## Network

### Get-NetworkStatus
- "What's my current network status?"
- "What's my external IP address?"
- "How fast is my network connection?"
- "What DNS servers am I using?"
- "How many active network connections do I have?"
- "Is anything making unexpected outbound connections?"
- "What's my local IP address?"
- "Which processes have active network connections?"
- "Am I connected to Wi-Fi or ethernet?"
- "What network adapters are active on this machine?"

---

## Windows Services & Events

### Get-ServiceStatus
- "Which services have stopped unexpectedly?"
- "Is the Everything search service running?"
- "What auto-start services are currently stopped?"
- "Is Windows Update service running?"
- "Show me all running services"
- "Is there anything that should be running but isn't?"
- "What services have been disabled?"
- "Is my print spooler running?"
- "Check if the Windows Search service is healthy"
- "Show me all services related to networking"

### Get-EventLogEntries
- "What errors have occurred on my system in the last 24 hours?"
- "Have there been any crashes or failures today?"
- "What happened on my machine last night?"
- "Are there any recurring errors I should know about?"
- "What warnings appeared in the Application log this week?"
- "Did anything crash while I was away?"
- "Show me critical errors from the last 48 hours"
- "What does the Security event log show recently?"
- "Are there any disk-related errors in my event log?"
- "What caused my machine to restart last time?"
- "Show me Windows Update related events"
- "Have there been any failed login attempts?"
- "What service failures have been logged this week?"

---

## Web

### Fetch-WebPage
- "Summarize the top stories on Hacker News right now"
- "What's the latest news on Reddit?"
- "Fetch this article and summarize it: [URL]"
- "What does the Wikipedia page for [topic] say?"
- "Summarize the release notes at this URL: [URL]"
- "What's on the front page of [news site] today?"
- "Fetch the README from this GitHub repo: [URL]"
- "What does this documentation page say about [topic]: [URL]"
- "Is this website up and what does it say?"
- "Summarize the investor relations page for [company]"
- "What are the key points on this page: [URL]"
- "Fetch and summarize this job listing: [URL]"

---

## Personal Knowledge

### Search-MyJoNotes
- "Search my devlog for anything about PowerClaw"
- "What have I written about trading setups lately?"
- "Find all journal entries tagged #bug"
- "What did I write about in my health notebook this month?"
- "Search my research notebook for anything about Playwright"
- "What projects have I been working on according to my journal?"
- "Find everything I've noted about AmiBroker"
- "What did I write in my watchlist notebook last week?"
- "Search my commonplace book for quotes about systems"
- "What have I written about Claude or AI tools?"
- "Find my notes about HomeChat"
- "Which notebook has more entries — trading or devlog?"
- "What did I log in my health notebook recently?"
- "Find all entries where I mentioned a specific ticker"
- "What was I working on two weeks ago according to my devlog?"
- "How much content do I have in MyJo total?"
- "Search my personal notebook for anything about goals"
- "Find entries where I used the tag #idea"
- "What did I write about mdview?"
- "Search my learning notebook for anything about PowerShell"

### Search-MnVault
- "What notes do I have about mdview?"
- "Search my vault for anything about Wits and Wagers"
- "What do my daily notes say about minimal-notes?"
- "Find vault notes related to Claude or AI agents"
- "What's in my agents section of the vault?"
- "Search for any notes tagged #decision"
- "What tool notes do I have?"
- "Find notes about the PowerShell profile setup"
- "Which has more content — mnvault or MyJo?"
- "What did I write in my daily notes last week?"
- "Search the vault for anything about HomeChat"
- "Find notes about the balance tracker"
- "What scripts do I have documented in the vault?"
- "Search for anything referencing Google Drive"

---

## Multi-Tool Chains

*These prompts require Claude to chain multiple tools in sequence.*

- "Give me a full health check — network, disk, services, and recent errors"
- "Is my machine healthy? Check CPU, RAM, storage, and event logs"
- "Find the biggest files I downloaded this year and tell me what they are"
- "What's taking up the most space on my system and what should I clean up?"
- "Check if any auto-start services are down and what errors relate to them"
- "Find all log files over 10MB and summarize what kind of errors are in them"
- "What am I working on right now? Check my devlog and active processes"
- "Is anything wrong with my machine? Run a full diagnostic"
- "Find the 5 biggest zip files in Downloads, tell me what they are, then ask if I want to delete them"
- "Compare my mnvault and MyJo in terms of content volume and topics covered"
- "What PowerShell scripts have I written recently and what do they do?"
- "Check the event log for disk errors and then show me my storage status"
- "What process is using the most resources and is it in my event log recently?"
- "Search my notes for anything about [topic] and also fetch the Wikipedia page on it"
- "Find my biggest Downloads, read any README files in them, and summarize what each is"
- "Check if the Everything service is running — if not, what errors are in the event log about it?"

---

## Meta / Diagnostic

- "What tools do you have available?"
- "What can you help me with?"
- "How many files are in my PowerClaw tools directory?"
- "Read the PowerClaw spec and tell me what Phase 3 involves"
- "What's in my PowerClaw log from today?"
