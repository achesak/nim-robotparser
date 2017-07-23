# Nim module for determining whether or not a particular user agent can fetch a URL on a website.
# Ported from Python's robotparser module (urllib.robotparser in Python 3).

# Written by Adam Chesak
# Released under the MIT open source license.


## nim-robotparser is a Nim module for determining whether or not a particular user agent can
## fetch a URL on a website. It is a port of Python's ``robotparser`` module (``urllib.robotparser``
## in Python 3).
##
## Usage examples
## ==============
##
## Basic use:
##
## .. code-block:: nimrod
##    
##    # Create a new robot parser and load a robots.txt file.
##    var robot : RobotParser = createRobotParser("http://www.google.com/robots.txt")
##    # Read from the robots.txt file.
##    robot.read()
##    # Can we fetch certain pages?
##    echo(robot.canFetch("*", "/maps/api/js?")    # Outputs true.
##    echo(robot.canFetch("*", "/search")          # Outputs false.
##    echo(robot.canFetch("*", "/musicsearch")     # Outputs false.
##
## Loading a URL after creation, and changing the ``robots.txt`` file:
## 
## .. code-block:: nimrod
##    
##    # Create a new robot parser, without specifying the URL yet.
##    var robot : RobotParser = createRobotParser()
##    # Now set the URL.
##    robot.setURL("http://www.google.com/robots.txt")
##    # Can now read and test in the same way as the previous example.
##    robot.read()
##    # It is also possible to use setURL() and read() to change the
##    # robots.txt file. Simply set the new URL and call read() again.
##    robot.setURL("http://en.wikipedia.org/robots.txt")
##    robot.read()
##
## Using the time procs to test when the ``robots.txt`` file was last parsed:
##
## .. code-block:: nimrod
##    
##    # Create another new robot parser.
##    var robot : RobotParser = createRobotParser("http://www.google.com/robots.txt")
##    # Read from the robots.txt file.
##    robot.read()
##    # ... more misc code here ...
##    # robots.txt file could be out of date here. Check to see if it's too old.
##    var time : Time = robot.mtime()
##    # If the file is more than ten second old (pulling numbers out of thin air here...),
##    # reload the file.
##    if time < getTime() - 10:
##        # Read the file again, and set the last modified time to now.
##        robot.read()
##        robot.modified()
##
## Checking for specific useragents:
##
## .. code-block:: nimrod
##    
##    # Create yet anothr robot parser. Let's use Wikipedia's robots.txt, as they
##    # have one that's nice and long. :)
##    var robot : RobotParser = createRobotParser("http://en.wikipedia.org/robots.txt")
##    # Read the rules.
##    robot.read()
##    # Check for pages using different useragents.
##    echo(robot.canFetch("WebCopier", "/"))             # Outputs false.
##    echo(robot.canFetch("ia_archiver", "/wiki"))       # Outputs true.
##    echo(robot.canFetch("ia_archiver", "/wiki/User"))  # Outputs false.
##    
##
## Note that nimrod-robotparser requires the ``robots.txt`` file to be valid and follows the
## correct format. Only minimal checks are done to make sure that the given file is correct.


import times
import httpclient
import strutils
import unicode
import sequtils
import re
import cgi
import uri


type
    RobotRule* = ref object
        path* : string
        allowance* : bool

    RobotEntry* = ref object
        useragents* : seq[string]
        rules* : seq[RobotRule]

    RobotParser* = ref object
        entries* : seq[RobotEntry]
        disallowAll* : bool
        allowAll* : bool
        url* : string
        lastChecked* : Time

proc createRobotParser*(url : string = ""): RobotParser
proc mtime*(robot : RobotParser): Time
proc modified*(robot : RobotParser) {.noreturn.}
proc setURL*(robot : RobotParser, url : string) {.noreturn.}
proc read*(robot : RobotParser) {.noreturn.}
proc parse*(robot : RobotParser, lines : seq[string]) {.noreturn.}
proc canFetch*(robot : RobotParser, useragent : string, url : string): bool
proc `$`*(robot : RobotParser): string
proc createEntry(): RobotEntry
proc `$`(entry : RobotEntry): string
proc appliesTo(entry : RobotEntry, useragent : string): bool
proc allowance(entry : RobotEntry, filename : string): bool
proc `$`(rule : RobotRule): string
proc createRule(path : string, allowance : bool): RobotRule
proc appliesTo(rule : RobotRule, filename : string): bool


proc quote(url : string): string = 
    ## Replaces special characters in url. Should have the same functionality as urllib.quote() in Python.
    
    var s : string = encodeUrl(url)
    s = s.replace("%2F", "/")
    s = s.replace("%2E", ".")
    s = s.replace("%2D", "-")
    return s


proc createRobotParser*(url : string = ""): RobotParser = 
    ## Creates a new robot parser with the specified URL.
    ##
    ## ``url`` is optional, as long as it is specified later using ``setURL()``.
    
    var r : RobotParser = RobotParser(entries: @[], lastChecked: getTime(), url: url, allowAll: false, disallowAll: false)
    #r.entries = @[] # This is probably a bad way of doing it. Currently it uses concat()
    return r         # from sequtils to add more as needed, but this can't be efficient.


proc mtime*(robot : RobotParser): Time = 
    ## Returns the time that the ``robot.txt`` file was last fetched.
    ##
    ## This is useful for long-running web spiders that need to check for new ``robots.txt`` files periodically.
    
    return robot.lastChecked


proc modified*(robot : RobotParser) =
    ## Sets the time the ``robots.txt`` file was last fetched to the current time.
    
    robot.lastChecked = getTime()


proc setURL*(robot : RobotParser, url : string) =
    ## Sets the URL referring to a ``robots.txt`` file.
    
    robot.url = url


proc read*(robot : RobotParser) = 
    ## Reads the ``robots.txt`` URL and feeds it to the parser.
    
    var s : string = newHttpClient().getContent(robot.url)
    var lines = s.splitLines()
    
    robot.parse(lines)


proc parse*(robot : RobotParser, lines : seq[string]) = 
    ## Parses the specified lines.
    ##
    ## This is meant as an internal proc (called by ``read()``), but can also be used to parse a
    ## ``robots.txt`` file without loading a URL.
    ##
    ## Example:
    ##
    ## .. code-block:: nimrod
    ##    
    ##    var parser : RobotParser = createParser()   # Note no URL specified.
    ##    var s : string = readFile("my_local_robots_file.txt")
    ##    var lines = s.splitLines()                   # Get the lines from a local file.
    ##    parser.parse(lines)                          # And parse them without loading from a remote server.
    ##    echo(parser.canFetch("*", "http://www.myserver.com/mypage.html") # Can now use normally.
    
    var state : int = 0
    var lineNumber : int = 0
    var entry : RobotEntry = createEntry()
    
    for line1 in lines:
         var line : string = line1.strip()
         lineNumber += 1
         if line == "":
             if state == 1:
                 entry = createEntry()
                 state = 0
             elif state == 2:
                 robot.entries = robot.entries.concat(@[entry]) # Please tell me there's a better way to do this.
         var i : int = line.find("#")
         if i >= 0:
             line = line[0..i-1]
         line = line.strip()
         if line == "":
             continue
         var lineSeq = line.split(':')
         if len(lineSeq) > 2:
             for j in 2..high(lineSeq):
                 lineSeq[1] &= lineSeq[j]
         if len(lineSeq) >= 2:
             lineSeq[0] = unicode.toLower(lineSeq[0].strip())
             lineSeq[1] = lineSeq[1].strip()
             if lineSeq[0] == "user-agent":
                 if state == 2:
                     robot.entries = robot.entries.concat(@[entry])
                     entry = createEntry()
                 entry.useragents = entry.useragents.concat(@[lineSeq[1]])
                 state = 1
             elif lineSeq[0] == "disallow":
                 entry.rules = entry.rules.concat(@[createRule(lineSeq[1], false)])
                 state = 2
             elif lineSeq[0] == "allow":
                 entry.rules = entry.rules.concat(@[createRule(lineSeq[1], true)])
                 state = 2
         if state == 2:
             robot.entries = robot.entries.concat(@[entry])
             


proc canFetch*(robot : RobotParser, useragent : string, url : string): bool = 
    ## Returns ``true`` if the useragent is allowed to fetch ``url`` according to the rules contained in the parsed ``robots.txt`` file,
    ## and ``false`` if it is not.
    
    if robot.allowAll:
        return true
    if robot.disallowAll:
        return false
    var uri : Uri = parseUri(url)
    var newUrl : string = quote(uri.path)
    if newUrl == "":
        newUrl = "/" 
    for entry in robot.entries:
        if entry.appliesTo(useragent):
            return entry.allowance(url)
    return true


proc `$`*(robot : RobotParser): string = 
    ## Operator to convert a RobotParser to a string.
    
    var s : string = ""
    for entry in robot.entries:
        s &= $entry & "\n"
    return s


proc createEntry(): RobotEntry = 
    ## Creates a new entry.
    
    var e : RobotEntry = RobotEntry(useragents: @[], rules: @[])
    return e


proc `$`(entry : RobotEntry): string =
    ## Operator to convert a RobotEntry to a string.
    
    var s : string = ""
    for i in entry.useragents:
        s &= "User-agent: " & i & "\n"
    for i in entry.rules:
        s &= $i & "\n"
    return s


proc appliesTo(entry : RobotEntry, useragent : string): bool = 
    ## Determines whether or not the entry applies to the specified agent.
    
    var useragent2 : string = unicode.toLower(useragent.split('/')[0])
    for agent in entry.useragents:
        if useragent2 == agent:
            if agent == "*":
                return true
            var agent2 : string = unicode.toLower(agent)
            if re.find(agent2, re(escapeRe(useragent2))) != -1:
                return true
    return false


proc allowance(entry : RobotEntry, filename : string): bool = 
    ## Determines whether or not a line is allowed.
    
    for line in entry.rules:
        if line.appliesTo(filename):
            return line.allowance
    return true


proc createRule(path : string, allowance : bool): RobotRule = 
    ## Creates a new rule.
    
    var r : RobotRule = RobotRule(path: quote(path), allowance: allowance)
    return r


proc `$`(rule : RobotRule): string = 
    ## Operator to convert a RobotRule to a string.
    
    var s : string
    if rule.allowance:
        s = "Allow: "
    else:
        s = "Disallow: "
    return s & rule.path


proc appliesTo(rule : RobotRule, filename : string): bool = 
    ## Determines whether ``filename`` applies to the specified rule.
    
    if rule.path == "%2A": # if rule.path == "*":
        return true
    return filename.find(decodeUrl(rule.path)) != -1
