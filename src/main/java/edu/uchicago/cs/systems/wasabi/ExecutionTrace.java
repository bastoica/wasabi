package edu.uchicago.cs.systems.wasabi;

import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.concurrent.locks.Lock;
import java.util.concurrent.locks.ReentrantLock;
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

class ExecutionTrace {

  private final Lock etLock = new ReentrantLock();
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
    etLock.lock();
    try {
      return this.opCache == null || this.opCache.isEmpty();
    } finally {
      etLock.unlock();
    }
  }

  public int getMaxOpCacheSize() {
    etLock.lock();
    try {
      return this.maxOpCacheSize;
    } finally {
      etLock.unlock();
    }
  }

  public int getSize() {
    etLock.lock();
    try {
      return this.opCache.size();
    } finally {
      etLock.unlock();
    }
  }

  public void addLast(OpEntry opEntry) {
    etLock.lock();
    try {
      if (this.maxOpCacheSize != this.INFINITE_CACHE && this.opCache.size() >= this.maxOpCacheSize) {
        this.opCache.removeFirst();
      }
      this.opCache.addLast(opEntry);
    } finally {
      etLock.unlock();
    }
  }

  public Boolean checkIfOpsAreEqual(int leftIndex, int rightIndex) {
    etLock.lock();
    try {
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

    } finally {
      etLock.unlock();
    }
  }

  public Boolean checkIfOpIsOfType(int targetIndex, int targetOpType) {
    etLock.lock();
    try {
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

    } finally {
      etLock.unlock();
    }
  }
  
  public Boolean checkIfOpHasFrame(int targetIndex, String targetFrame) {
    etLock.lock();
    try {
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

    } finally {
      etLock.unlock();
    }
  }
}