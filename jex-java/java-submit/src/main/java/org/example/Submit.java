package org.example;

import picocli.CommandLine;

public class Submit {

    public static void main(String[] args) throws Exception {
        // note: setTrimQuotes(true) required to be able to do --arg=\"--arg=foo\"
        SubmitCommand command = new SubmitCommand(submitArgs -> new Submitter(submitArgs).submit());
        System.exit(new CommandLine(command).setTrimQuotes(true).execute(args));
    }
}
