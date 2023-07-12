package edu.uchicago.cs.systems.wasabi;

class InjectionPoint {

  public StackSnapshot stackSnapshot = null;
  public String retryLocation = null;
  public String retryCaller = null;
  public String retriedCallee = null;
  public String retriedException = null;
  Double injectionProbability = 0.0;
  public Integer injectionCount = 0;

  public InjectionPoint(StackSnapshot stackSnapshot, 
                        String retryLocation,
                        String retryCaller,
                        String retriedCallee,
                        String retriedException,
                        Double injectionProbability,
                        Integer injectionCount) {
    this.stackSnapshot = stackSnapshot;
    this.retryLocation = retryLocation;
    this.retryCaller = retryCaller;
    this.retriedCallee = retriedCallee;
    this.retriedException = retriedException;
    this.injectionProbability = injectionProbability;
    this.injectionCount = injectionCount;
    }

  public Boolean isEmpty() {
    return (
      this.stackSnapshot.isNullOrEmpty() &&
      this.retryLocation == null && 
      this.retryCaller == null &&
      this.retriedCallee == null &&
      this.retriedException == null
    );
  }
}