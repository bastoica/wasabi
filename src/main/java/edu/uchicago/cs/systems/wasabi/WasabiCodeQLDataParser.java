package edu.uchicago.cs.systems.wasabi;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.io.BufferedReader;
import java.io.FileReader;
import java.io.IOException;
import java.lang.System;
import java.util.ArrayList;
import java.util.HashMap;

public class WasabiCodeQLDataParser {

	private static final Logger LOG = LoggerFactory.getLogger(WasabiCodeQLDataParser.class);

    private ArrayList<String[]> rawRecords = new ArrayList<>();
    private HashMap<String, WasabiWaypoint> waypoints = new HashMap<>();
    private HashMap<String, HashMap<String, String>> callersToExceptionsMap = new HashMap<>();
    private HashMap<String, String> reverseRetryLocationsMap = new HashMap<>();
    private HashMap<String, Double> injectionProbabilityMap = new HashMap<>();
    
    private String csvFileName = System.getProperty("csvFileName");

    private static final String[] CSV_COLUMN_NAMES = {"Retry location", "Enclosing method", "Retried method", "Exception", "Injection Probablity", "Test coverage"};
   
    public void parseCodeQLOutput() {
        try {
            BufferedReader br = new BufferedReader(new FileReader(this.csvFileName));

            boolean foundHeader = false;
            String line;
            while ((line = br.readLine()) != null) {
                String[] values = line.split("!!!");

                if (!foundHeader && arrayEquals(CSV_COLUMN_NAMES, values)) {
                    foundHeader = true;
                    continue;
                }

                if (foundHeader) {
                    rawRecords.add(values);
                }
            }

        } catch (IOException e) {
			LOG.debug("[wasabi] An exception occured in the parser code: " + e.getMessage());
            e.printStackTrace();
        }

        for (String[] record : rawRecords) {
            String retryLocation = record[0];
            String retryCaller = record[1];
            String retriedCallee = record[2];
            String retriedException = record[3];
            String injectionProbabilityString = record[4];

            String key = WasabiWaypoint.getHashValue(retryLocation, retryCaller, retriedCallee, retriedException);
            WasabiWaypoint waypoint = waypoints.get(key);
            if (waypoint == null) {
                waypoint = new WasabiWaypoint(retryLocation, retryCaller, retriedCallee, retriedException);
                waypoints.put(key, waypoint);
            }

            HashMap<String, String> calleesToExceptionsMap = callersToExceptionsMap.computeIfAbsent(retryCaller, v -> new HashMap<>());
            calleesToExceptionsMap.put(retriedCallee, retriedException);

            key = WasabiWaypoint.getHashValue(retryCaller, retriedCallee, retriedException);
            reverseRetryLocationsMap.put(key, retryLocation);
            
            try {
                Double injectionProbablity = Double.parseDouble(injectionProbabilityString);
                injectionProbabilityMap.put(key, injectionProbablity);
            } catch (Exception e) {
                LOG.error("[wasabi] Parsing line " + record[0] + " , " + record[1] + " , " + record[2] + " , " + record[3] + " , " + record[4] + " , " + record[5]);
                LOG.error("[wasabi] An exception occured when parsing the injection probabilites: " + e.getMessage());
                e.printStackTrace();
            }
            
        }
    }

    private static boolean arrayEquals(String[] sourceArray, String[] targetArray) {
        if (sourceArray.length != targetArray.length) {
            return false;
        }
        for (int i = 0; i < sourceArray.length; i++) {
            if (!sourceArray[i].equals(targetArray[i])) {
                return false;
            }
        }
        return true;
    }

    public ArrayList<String[]> getRawRecords() {
        return rawRecords;
    }

    public HashMap<String, WasabiWaypoint> getWaypoints() {
        return waypoints;
    }

    public HashMap<String, HashMap<String, String>> getCallersToExceptionsMap() {
        return callersToExceptionsMap;
    }

    public HashMap<String, String> getReverseRetryLocationsMap() {
        return reverseRetryLocationsMap;
    }

    public HashMap<String, Double> getInjectionProbabilityMap() {
        return injectionProbabilityMap;
    }
}