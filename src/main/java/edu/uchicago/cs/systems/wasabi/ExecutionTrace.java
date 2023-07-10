package edu.uchicago.cs.systems.wasabi;

import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Deque;
import java.util.Iterator;
import java.util.LinkedList;
import java.util.Objects;

class OpEntry {

  public static final Integer RETRY_CALLER_OP = 0;
  public static final Integer THREAD_SLEEP_OP = 1;

  private Integer opType = this.RETRY_CALLER_OP;
  private StackSnapshot stackSnapshot = null;
  private Long timestamp = 0L;
  private String exception = null;

  public OpEntry(Integer opType,
                 Long timestamp, 
                 StackSnapshot stackSnapshot) {
    this.opType = opType;
    this.timestamp = timestamp;
    this.stackSnapshot = stackSnapshot;
    this.exception = null;
  }

  public OpEntry(Integer opType,
                 Long timestamp, 
                 StackSnapshot stackSnapshot,
                 String exception) {
    this.opType = opType;
    this.timestamp = timestamp;
    this.stackSnapshot = stackSnapshot;
    this.exception = exception;
  }

  public OpEntry(Integer opType,
                 StackSnapshot stackSnapshot,
                 String exception) {
    this.opType = opType;
    this.timestamp = 0L;
    this.stackSnapshot = stackSnapshot;
    this.exception = exception;
  }

  public Boolean isOfType(Integer opType) {
    return Objects.equals(this.opType, opType);
  }

  public Boolean hasFrame(String target) {
    return this.stackSnapshot.hasFrame(target);
  }

  public Boolean isSameOp(OpEntry target) {      
    return ( 
        this.opType == target.opType && 
        this.exception.equals(target.exception) &&
        this.stackSnapshot.isEqual(target.stackSnapshot)
      );
  }
}

public class ExecutionTrace {

  private final int INFINITE_CACHE = -1; 

  private ArrayDeque<OpEntry> opCache;
  private int maxOpCacheSize;

  public ExecutionTrace() {
    this.opCache = new ArrayDeque<OpEntry>(); 
    this.maxOpCacheSize = this.INFINITE_CACHE;
  }

  public ExecutionTrace(int maxOpCacheSize) {
    this.opCache = new ArrayDeque<OpEntry>(); 
    this.maxOpCacheSize = maxOpCacheSize;
  }

  public Boolean isNullOrEmpty() {
    return this.opCache == null || this.opCache.isEmpty();
  }

  public int getMaxOpCacheSize() {
    return this.maxOpCacheSize;
  }

  public int getSize() {
    return this.opCache.size();
  }

  public void addLast(OpEntry opEntry) {
    if (this.maxOpCacheSize != this.INFINITE_CACHE && this.opCache.size() >= this.maxOpCacheSize) {
      this.opCache.removeFirst();
    }
    this.opCache.addLast(opEntry);
  }

  public Boolean checkIfOpsAreEqual(int leftIndex, int rightIndex) {
    if (this.opCache.size() < Math.max(leftIndex, rightIndex)) {
      return false;
    }

    OpEntry leftOp = null;
    OpEntry rightOp = null;

    int index = this.opCache.size() - 1; 
    Iterator<OpEntry> itr = this.opCache.descendingIterator();
    while (itr.hasNext() && index >= Math.min(leftIndex, rightIndex)) {
      OpEntry current = itr.next();

      if (index == leftIndex) {
        leftOp = current;
      } else if (index == rightIndex) {
        rightOp = current;
      }

      --index;
    }

    return leftOp != null && rightOp != null && leftOp.isSameOp(rightOp);
  }

  public Boolean checkIfOpIsOfType(int targetIndex, int targetOpType) {
    if (this.opCache.size() < targetIndex) {
      return false;
    }

    OpEntry targetOp = null;

    int index = this.opCache.size() - 1; 
    Iterator<OpEntry> itr = this.opCache.descendingIterator();
    while (itr.hasNext() && index >= targetIndex) {
      OpEntry current = itr.next();

      if (index == targetIndex) {
        targetOp = current;
      }

      --index;
    }

    return targetOp != null && targetOp.isOfType(targetOpType);
  }
  
  public Boolean checkIfOpHasFrame(int targetIndex, String targetFrame) {
    if (this.opCache.size() < targetIndex) {
      return false;
    }

    OpEntry targetOp = null;

    int index = this.opCache.size() - 1; 
    Iterator<OpEntry> itr = this.opCache.descendingIterator();
    while (itr.hasNext() && index >= targetIndex) {
      OpEntry current = itr.next();

      if (index == targetIndex) {
        targetOp = current;
      }

      --index;
    }

    return targetOp != null && targetOp.hasFrame(targetFrame);
  }
}