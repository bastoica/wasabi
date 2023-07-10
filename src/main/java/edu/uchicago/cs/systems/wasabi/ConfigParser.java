package edu.uchicago.cs.systems.wasabi;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.io.BufferedReader;
import java.io.FileReader;
import java.io.IOException;
import java.lang.System;
import java.util.Arrays;
import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.Map;

public class ConfigParser {

  private static WasabiLogger LOG;

  private static final ArrayList<String[]> rawRecords = new ArrayList<>();
  private static final Map<String, HashMap<String, String>> callersToExceptionsMap = new HashMap<>();
  private static final Map<Integer, String> reverseRetryLocationsMap = new HashMap<>();
  private static final Map<Integer, Double> injectionProbabilityMap = new HashMap<>();
  
  private static final HashingPrimitives hashingPrimitives = new HashingPrimitives();
  private static final String csvFileName = System.getProperty("csvFileName");
  private static final String[] CSV_COLUMN_NAMES = {"Retry location", "Enclosing method", "Retried method", "Exception", "Injection Probablity", "Test coverage"};
  
  public ConfigParser(WasabiLogger logger) {
    LOG = logger;
  }

  public void parseCodeQLOutput() {
    try (BufferedReader br = new BufferedReader(new FileReader(this.csvFileName))) {
      boolean foundHeader = false;
      String line;
      while ((line = br.readLine()) != null) {
        String[] values = line.split("!!!");

        if (!foundHeader && Arrays.equals(CSV_COLUMN_NAMES, values)) {
          foundHeader = true;
          continue;
        }

        if (foundHeader) {
          rawRecords.add(values);
        }
      }
    } catch (IOException e) {
      LOG.printMessage(
          LOG.LOG_LEVEL_ERROR, 
          String.format("[wasabi] An exception occured in the parser code: %s\n", e.getMessage())
        );
      e.printStackTrace();
    }

    for (String[] record : rawRecords) {
      String retryLocation = record[0];
      String retryCaller = record[1];
      String retriedCallee = record[2];
      String retriedException = record[3];
      String injectionProbabilityString = record[4];

      HashMap<String, String> calleesToExceptionsMap = callersToExceptionsMap.computeIfAbsent(retryCaller, v -> new HashMap<>());
      calleesToExceptionsMap.put(retriedCallee, retriedException);

      int key = hashingPrimitives.getHashValue(retryCaller, retriedCallee, retriedException);
      reverseRetryLocationsMap.put(key, retryLocation);
      
      try {
        Double injectionProbablity = Double.parseDouble(injectionProbabilityString);
        injectionProbabilityMap.put(key, injectionProbablity);
      } catch (Exception e) {
        LOG.printMessage(
            LOG.LOG_LEVEL_ERROR, 
            String.format("[wasabi] An exception occured when parsing parsing entry ( %s , %s , %s , %s ): %s\n", 
              record[0], record[1], record[2], record[3], e.getMessage())
          );
        e.printStackTrace();
      }
    }
  }

  private ArrayList<String[]> getRawRecords() {
    return rawRecords;
  }

  public Map<String, HashMap<String, String>> getCallersToExceptionsMap() {
    return Collections.unmodifiableMap(callersToExceptionsMap);
  }

  public Map<Integer, String> getReverseRetryLocationsMap() {
    return Collections.unmodifiableMap(reverseRetryLocationsMap);
  }

  public Map<Integer, Double> getInjectionProbabilityMap() {
    return Collections.unmodifiableMap(injectionProbabilityMap);
  }
}
