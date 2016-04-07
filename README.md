About
=====

nim-robotparser is a Nim module for using robot.txt files to determine whether or not a particular user agent can fetch a URL on a website. It is a port of Python's robotparser module.

Usage examples
==============

Basic use:

    # Create a new robot parser and load a robots.txt file.
    var robot : RobotParser = createRobotParser("http://www.google.com/robots.txt")
    # Read from the robots.txt file.
    robot.read()
    # Can we fetch certain pages?
    echo(robot.canFetch("*", "/maps/api/js?")    # Outputs true.
    echo(robot.canFetch("*", "/search")          # Outputs false.
    echo(robot.canFetch("*", "/musicsearch")     # Outputs false.

Loading a URL after creation, and changing the ``robots.txt`` file:
    
    # Create a new robot parser, without specifying the URL yet.
    var robot : RobotParser = createRobotParser()
    # Now set the URL.
    robot.setURL("http://www.google.com/robots.txt")
    # Can now read and test in the same way as the previous example.
    robot.read()
    # It is also possible to use setURL() and read() to change the
    # robots.txt file. Simply set the new URL and call read() again.
    robot.setURL("http://en.wikipedia.org/robots.txt")
    robot.read()

Using the time procs to test when the ``robots.txt`` file was last parsed:
  
    # Create another new robot parser.
    var robot : RobotParser = createRobotParser("http://www.google.com/robots.txt")
    # Read from the robots.txt file.
    robot.read()
    # ... more misc code here ...
    # robots.txt file could be out of date here. Check to see if it's too old.
    var time : Time = robot.mtime()
    # If the file is more than ten second old (pulling numbers out of thin air here...),
    # reload the file.
    if time < getTime() - 10:
        # Read the file again, and set the last modified time to now.
        robot.read()
        robot.modified()

Checking for specific useragents:

    # Create yet anothr robot parser. Let's use Wikipedia's robots.txt, as they
    # have one that's nice and long. :)
    var robot : RobotParser = createRobotParser("http://en.wikipedia.org/robots.txt")
    # Read the rules.
    robot.read()
    # Check for pages using different useragents.
    echo(robot.canFetch("WebCopier", "/"))             # Outputs false.
    echo(robot.canFetch("ia_archiver", "/wiki"))       # Outputs true.
    echo(robot.canFetch("ia_archiver", "/wiki/User"))  # Outputs false.
    
Note that nimrod-robotparser requires the ``robots.txt`` file to be valid and follows the
correct format. Only minimal checks are done to make sure that the given file is correct.

License
=======

nim-robotparser is released under the MIT open source license.
