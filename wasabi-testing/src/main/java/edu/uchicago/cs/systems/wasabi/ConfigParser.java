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

import edu.uchicago.cs.systems.wasabi.InjectionPoint;

import org.junit.Assert;

class ConfigParser {

  private static WasabiLogger LOG;
  private static String configFile;

  private static String retryDataFile;
  private static String injectionPolicy;
  private static int maxInjectionCount;
  
  private static final ArrayList<String[]> rawRecords = new ArrayList<>();
  private static final Map<String, InjectionPoint> injectionPlan = new HashMap<>();
  
  private static final HashingPrimitives hashingPrimitives = new HashingPrimitives();
  private static final String[] RETRY_DATA_COLUMN_NAMES = {"Retry location", "Retry caller", "Injection site", "Injection location", "Exception"};
  
  public ConfigParser(WasabiLogger logger, String configFile) {
    this.LOG = logger;
    this.configFile = configFile;

    parseConfigFile();
    parseCodeQLOutput();
  }

  private void parseConfigFile() {
    try (BufferedReader br = new BufferedReader(new FileReader(this.configFile))) {
      String line;
      while ((line = br.readLine()) != null) {
        String[] parts = line.split(":");
        Assert.assertEquals("[wasabi] Invalid line format for <" + line + ">", 2, parts.length);

        String parameter = parts[0].trim();
        String value = parts[1].replaceAll("\\s+", "").trim();
        switch (parameter) {
          case "retry_data_file":
            this.retryDataFile = value;
            break;
          case "injection_policy":
            this.injectionPolicy = value;
            break;
          case "max_injection_count":
            try {
              this.maxInjectionCount = Integer.parseInt(value);
            } catch (Exception e) {
              this.LOG.printMessage(
                  LOG.LOG_LEVEL_ERROR, 
                  String.format("An exception occurred when parsing line <%s>: %s\n", 
                    line, e.getMessage())
                );
              e.printStackTrace();
            }
            break;
        }
      }
    } catch (IOException e) {
      this.LOG.printMessage(
          LOG.LOG_LEVEL_ERROR, 
          String.format("An exception occurred when parsing the config file: %s\n", e.getMessage())
        );
      e.printStackTrace();
    }
  }

  private void parseCodeQLOutput() {
    try (BufferedReader br = new BufferedReader(new FileReader(this.retryDataFile))) {
      boolean foundHeader = false;
      String line;
      while ((line = br.readLine()) != null) {
        String[] values = line.split("!!!");

        if (!foundHeader && Arrays.equals(RETRY_DATA_COLUMN_NAMES, values)) {
          foundHeader = true;
          continue;
        }

        if (foundHeader) {
          rawRecords.add(values);
        }
      }
    } catch (IOException e) {
      this.LOG.printMessage(
          LOG.LOG_LEVEL_ERROR, 
          String.format("An exception occurred when parsing the retry data file: %s\n", e.getMessage())
        );
      e.printStackTrace();
    }

    for (String[] record : rawRecords) {
      String retrySourceLocation = record[0];
      String retryCallerFunction = record[1];
      String injectionSite = record[2];
      String injectionLocation = record[3];
      String retryException = record[4];

      InjectionPoint entry = new InjectionPoint(
        null,
        retrySourceLocation,
        retryCallerFunction,
        injectionSite,
        retryException,
        -1
      );
      
      injectionPlan.put(injectionLocation, entry);
    }
  }

  public ArrayList<String[]> getRawRecords() {
    return rawRecords;
  }

  public Map<String, InjectionPoint> getInjectionPlan() {
    return Collections.unmodifiableMap(injectionPlan);
  }

  public int getMaxInjectionCount() {
    return this.maxInjectionCount;
  }

  public String getInjectionPolicy() {
    return this.injectionPolicy;
  }
}
