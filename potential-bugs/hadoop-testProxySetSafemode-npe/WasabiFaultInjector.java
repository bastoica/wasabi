/** 
 * WASABI 0.9
 * Lightweight fault injection class that trows exceptions (e.g. SocketTimeoutException).
**/

package org.apache.hadoop.util;

import java.io.IOException;
import java.util.concurrent.TimeoutException;
import java.lang.reflect.InvocationTargetException;

import java.net.ConnectException;
import java.net.SocketException;
import java.net.SocketTimeoutException;

import org.apache.hadoop.net.ConnectTimeoutException;
import org.apache.hadoop.ipc.RemoteException;
import org.apache.hadoop.ipc.RetriableException;

import org.apache.zookeeper.KeeperException;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
 
public class WasabiFaultInjector {
  /* 
   * Private helper methods
   */

  private static final int MAX_FAULTS = -1;
  private int faultCount;
  private static final Logger LOG = LoggerFactory.getLogger(WasabiFaultInjector.class);
   
  
  StackTraceElement[] getCurrentStack() {
    return Thread.currentThread().getStackTrace();
  }

  String getTestName() {
    StackTraceElement[] stack = this.getCurrentStack();
    
    for (int depth = 1; depth < stack.length; ++depth) {
      StackTraceElement frame = stack[depth];
      if (frame.getClassName().contains(".Test") && frame.getMethodName().contains(",test")) {
        return frame.getClassName() + "." + 
               frame.getMethodName() + "(" + frame.getFileName() + 
               ":" + frame.getLineNumber() + ")";
      }
    }

    return "(null)";
  }

  
  /* 
   * Public APIs
   */

  public WasabiFaultInjector() {
    this.faultCount = 0;
  }

  public void injectException(Exception e, String msg) throws Exception {
    if (this.MAX_FAULTS < 0 || this.faultCount < this.MAX_FAULTS) {
      this.faultCount++;
      this.LOG.warn("[wasabi]: [thread: " + Thread.currentThread().getId() + "]: " + msg + ", fault count: " + this.faultCount + ", test: " + this.getTestName());
      throw e;
    } else {
      this.LOG.warn("[wasabi]: [thread: " + Thread.currentThread().getId() + "]: Stop injection, fall through, " + this.getTestName());
    }
  }

  public void injectIOException(IOException e, String msg) throws IOException {
    if (this.MAX_FAULTS < 0 || this.faultCount < this.MAX_FAULTS) {
      this.faultCount++;
      this.LOG.warn("[wasabi]: [thread: " + Thread.currentThread().getId() + "]: " + msg + ", fault count: " + this.faultCount + ", test: " + this.getTestName());
      throw e;
    } else {
      this.LOG.warn("[wasabi]: [thread: " + Thread.currentThread().getId() + "]: Stop injection, fall through, " + this.getTestName());
    }
  }

  public void injectSocketException(SocketException e, String msg) throws SocketException {
    if (this.MAX_FAULTS < 0 || this.faultCount < this.MAX_FAULTS) {
      this.faultCount++;
      this.LOG.warn("[wasabi]: [thread: " + Thread.currentThread().getId() + "]: " + msg + ", fault count: " + this.faultCount + ", test: " + this.getTestName());
      throw e;
    } else {
      this.LOG.warn("[wasabi]: [thread: " + Thread.currentThread().getId() + "]: Stop injection, fall through, " + this.getTestName());
    }
  }

  public void injectSocketTimeoutException(SocketTimeoutException e, String msg) throws SocketTimeoutException {
    if (this.MAX_FAULTS < 0 || this.faultCount < this.MAX_FAULTS) {
      this.faultCount++;
      this.LOG.warn("[wasabi]: [thread: " + Thread.currentThread().getId() + "]: " + msg + ", fault count: " + this.faultCount + ", test: " + this.getTestName());
      throw e;
    } else {
      this.LOG.warn("[wasabi]: [thread: " + Thread.currentThread().getId() + "]: Stop injection, fall through, " + this.getTestName());
    }
  }

  public void injectConnectException(ConnectException e, String msg) throws ConnectException {
    if (this.MAX_FAULTS < 0 || this.faultCount < this.MAX_FAULTS) {
      this.faultCount++;
      this.LOG.warn("[wasabi]: [thread: " + Thread.currentThread().getId() + "]: " + msg + ", fault count: " + this.faultCount + ", test: " + this.getTestName());
      throw e;
    } else {
      this.LOG.warn("[wasabi]: [thread: " + Thread.currentThread().getId() + "]: Stop injection, fall through, " + this.getTestName());
    }
  }

  public void injectConnectTimeoutException(ConnectTimeoutException e, String msg) throws ConnectTimeoutException {
    if (this.MAX_FAULTS < 0 || this.faultCount < this.MAX_FAULTS) {
      this.faultCount++;
      this.LOG.warn("[wasabi]: [thread: " + Thread.currentThread().getId() + "]: " + msg + ", fault count: " + this.faultCount + ", test: " + this.getTestName());
      throw e;
    } else {
      this.LOG.warn("[wasabi]: [thread: " + Thread.currentThread().getId() + "]: Stop injection, fall through, " + this.getTestName());
    }
  }

  public void injectTimeoutException(TimeoutException e, String msg) throws TimeoutException {
    if (this.MAX_FAULTS < 0 || this.faultCount < this.MAX_FAULTS) {
      this.faultCount++;
      this.LOG.warn("[wasabi]: [thread: " + Thread.currentThread().getId() + "]: " + msg + ", fault count: " + this.faultCount + ", test: " + this.getTestName());
      throw e;
    } else {
      this.LOG.warn("[wasabi]: [thread: " + Thread.currentThread().getId() + "]: Stop injection, fall through, " + this.getTestName());
    }
  }
  
  public void injectRetriableException(RetriableException e, String msg) throws RetriableException {
    if (this.MAX_FAULTS < 0 || this.faultCount < this.MAX_FAULTS) {
      this.faultCount++;
      this.LOG.warn("[wasabi]: [thread: " + Thread.currentThread().getId() + "]: " + msg + ", fault count: " + this.faultCount + ", test: " + this.getTestName());
      throw e;
    } else {
      this.LOG.warn("[wasabi]: [thread: " + Thread.currentThread().getId() + "]: Stop injection, fall through, " + this.getTestName());
    }
  }

  public void injectInvocationTargetException(InvocationTargetException e, String msg) throws InvocationTargetException {
    if (this.MAX_FAULTS < 0 || this.faultCount < this.MAX_FAULTS) {
      this.faultCount++;
      this.LOG.warn("[wasabi]: [thread: " + Thread.currentThread().getId() + "]: " + msg + ", fault count: " + this.faultCount + ", test: " + this.getTestName());
      throw e;
    } else {
      this.LOG.warn("[wasabi]: [thread: " + Thread.currentThread().getId() + "]: Stop injection, fall through, " + this.getTestName());
    }
  }

  public void injectRemoteException(RemoteException e, String msg) throws RemoteException {
    if (this.MAX_FAULTS < 0 || this.faultCount < this.MAX_FAULTS) {
      this.faultCount++;
      this.LOG.warn("[wasabi]: [thread: " + Thread.currentThread().getId() + "]: " + msg + ", fault count: " + this.faultCount + ", test: " + this.getTestName());
      throw e;
    } else {
      this.LOG.warn("[wasabi]: [thread: " + Thread.currentThread().getId() + "]: Stop injection, fall through, " + this.getTestName());
    }
  }
  
  public void injectKeeperException(KeeperException e, String msg) throws KeeperException {
    if (this.MAX_FAULTS < 0 || this.faultCount < this.MAX_FAULTS) {
      this.faultCount++;
      this.LOG.warn("[wasabi]: [thread: " + Thread.currentThread().getId() + "]: " + msg + ", fault count: " + this.faultCount + ", test: " + this.getTestName());
      throw e;
    } else {
      this.LOG.warn("[wasabi]: [thread: " + Thread.currentThread().getId() + "]: Stop injection, fall through, " + this.getTestName());
    }
  }
  
  public void printCallstack(String location) {
    this.LOG.warn("[wasabi]: Stack trace at " + location + " (thread id: " + Thread.currentThread().getId() + "): ");
    
    StackTraceElement[] stack = getCurrentStack();
    for (int depth = 1; depth < stack.length; ++depth) {
      StackTraceElement frame = stack[depth];
      this.LOG.warn("\tat " + frame.getClassName() + "." + 
                    frame.getMethodName() + "(" + frame.getFileName() + 
                    ":" + frame.getLineNumber() + ")");
    }
  }

  public void printMsg(String msg) {
    this.LOG.warn("[wasabi]: [thread: " + Thread.currentThread().getId() + "]: " + msg);
  }
 }
