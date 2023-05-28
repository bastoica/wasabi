package edu.uchicago.cs.systems.wasabi;

import java.util.HashMap;

public class WasabiWaypoint {
    private String retryLocation;
    private String retryCaller;
    private String retriedCallee;
    private String retriedException;

    public WasabiWaypoint(String retryLocation, String retryCaller, String retriedCallee, String retriedException) {
        this.retryLocation = retryLocation;
        this.retryCaller = retryCaller;
        this.retriedCallee = retriedCallee;
        this.retriedException = retriedException;
    }

    public String getRetryLocation() {
        return retryLocation;
    }

    public String getRetryCaller() {
        return retryCaller;
    }

    public String getRetriedCallee() {
        return retriedCallee;
    }

    public String getRetriedException() {
        return retriedException;
    }

    public static String getHashValue(String retryLocation, String retryCaller, String retriedCallee, String retriedException) {
        return retryLocation + "@" + retryCaller + "@" + retriedCallee + "@" + retriedException;
    }
}
