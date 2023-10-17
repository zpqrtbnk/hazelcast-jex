package org.example;

import picocli.CommandLine;

public class Submit {

    public static void main(String[] args) throws Exception {
        SubmitCommand command = new SubmitCommand(submitArgs -> new Submitter(submitArgs).submit());
        System.exit(new CommandLine(command).execute(args));
    }
}
