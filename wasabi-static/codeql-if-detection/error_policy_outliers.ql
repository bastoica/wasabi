/**
 * @kind problem
 * @id IF-problem
 * @problem.severity warning
 */

import java
import semmle.code.java.ControlFlowGraph

class GithubLocation extends Location {
  string getGithubURL() {
  	result = "https://github.com/%%GITHUB_ORG%%/%%APP_NAME%%/tree/" + "/" +
				"%%COMMIT_SHA%%" + "/" +
				this.toString().replaceAll("file:///opt/src", "").regexpReplaceAll(":(\\d+):\\d+:\\d+:\\d+$", "#L$1")
  }
}

string appName() {
	result = "%%APP_NAME%%_%%COMMIT_SHA%%"
}

predicate isRetryLoop(LoopStmt l) {

  (not l instanceof EnhancedForStmt)
		and
  (exists(Expr e | e.getAnEnclosingStmt() = l and (e instanceof VarAccess or e instanceof MethodAccess) and
                        (e.toString().toLowerCase().matches("%retry%") or e.toString().toLowerCase().matches("%retries%")))

        or
    exists (StringLiteral s | s.getAnEnclosingStmt() = l and (s.getValue().matches("%retry%") or s.getValue().matches("%retries%"))))
	and
  (hasExceptionHandling(l) or exists(Exception e | e.getName() != "InterruptedException" and e = l.getEnclosingCallable().getAnException()))


}

predicate hasExceptionHandling(Stmt s) {
	exists(CatchClause cc | not cc.getACaughtType().toString().matches("%InterruptedException%") and cc.getEnclosingStmt*() = s)
}

predicate isSource(Element e) {
 not e.getCompilationUnit().getFile().getRelativePath().toLowerCase().matches("%test%")
}

predicate isJavaMethod(Method m) {
  m.getQualifiedName().matches("java%") or m.getQualifiedName().matches("%slf4j%")
}

predicate isCaughtTopLevel(LoopStmt loop, CatchClause cc) {
	cc.getEnclosingStmt*() = loop
			and
	not exists(CatchClause cc2 | cc != cc2 and cc2.getEnclosingStmt*() = loop and cc.getEnclosingStmt*() = cc2.getBlock())

}

predicate hasSuccessor(ControlFlowNode node, Expr expr) {
	node.getASuccessor().(Expr).getParent*() = expr
		or
	hasSuccessor(node.getANormalSuccessor(), expr)
}

predicate isCaughtAndRetried(LoopStmt loop, RefType ex) {
	exists(CatchClause cc | isCaughtTopLevel(loop,cc)
			and
			not exists(CatchClause sup | sup != cc and isCaughtTopLevel(loop, sup) and (sup.getACaughtType() = ex or sup.getACaughtType().getADescendant()=ex)
				and cc.getTry() = sup.getTry() and sup.getIndex() < cc.getIndex())
			and
			(cc.getACaughtType() = ex or (cc.getACaughtType() != ex and cc.getACaughtType().getADescendant() = ex))
			and
			exists(MethodAccess ma | ma.getEnclosingStmt().getEnclosingStmt*() = cc.getTry() and ma.getMethod().getAThrownExceptionType() = ex)
			and
			exists(Expr loopReentry, ControlFlowNode last |
				if exists(loop.(ForStmt).getAnUpdate())
				then loopReentry = loop.(ForStmt).getUpdate(0)
				else loopReentry = loop.getCondition()
			|
				last.getEnclosingStmt().getEnclosingStmt*() = cc.getBlock() and
				hasSuccessor(last, loopReentry)
			))

}


predicate isCaughtAndNotRetried(LoopStmt loop, RefType ex) {
	exists(CatchClause cc | isCaughtTopLevel(loop,cc)
			and
			not exists(CatchClause sup | sup != cc and isCaughtTopLevel(loop, sup) and (sup.getACaughtType() = ex or sup.getACaughtType().getADescendant()=ex)
				and cc.getTry() = sup.getTry() and sup.getIndex() < cc.getIndex())
			and
			(cc.getACaughtType() = ex or (cc.getACaughtType() != ex and cc.getACaughtType().getADescendant() = ex))
			and
			exists(MethodAccess ma | ma.getEnclosingStmt().getEnclosingStmt*() = cc.getTry() and ma.getMethod().getAThrownExceptionType() = ex)
			and
			not exists(Expr loopReentry, ControlFlowNode last |
				if exists(loop.(ForStmt).getAnUpdate())
				then loopReentry = loop.(ForStmt).getUpdate(0)
				else loopReentry = loop.getCondition()
			|
				last.getEnclosingStmt().getEnclosingStmt*() = cc.getBlock() and
				hasSuccessor(last, loopReentry)
			))
}

predicate isNotCaught(LoopStmt loop, RefType ex) {
	exists(MethodAccess ma | ma.getAnEnclosingStmt() = loop and ma.getMethod().getAThrownExceptionType() = ex and
			not exists(CatchClause cc | ma.getAnEnclosingStmt() = cc) and
			not exists(CatchClause cc | ma.getAnEnclosingStmt() = cc.getTry() and cc.getEnclosingStmt*() = loop and cc.getACaughtType().getADescendant() = ex))

}

predicate isNotRetried(LoopStmt loop, RefType ex) {
	isCaughtAndNotRetried(loop, ex) or isNotCaught(loop, ex)
}

string getMethodList(LoopStmt loop, RefType ex) {
	result = "(" + concat(MethodAccess ma |
							ma.getAnEnclosingStmt() = loop and
							ma.getMethod().getAThrownExceptionType() = ex and
							not exists(CatchClause cc | ma.getAnEnclosingStmt() = cc)
					| ma.getMethod().getName()+"#"+ma.getLocation().getStartLine(), ";") + ")"
}

predicate isGenericJavaException(RefType ex) {
	ex.getQualifiedName().matches("java.io.IOException") or
	ex.getQualifiedName().matches("java.lang.RuntimeException") or
	ex.getQualifiedName().matches("java.lang.Exception") or
	ex.getQualifiedName().matches("java.lang.InterruptedException")
}

from ThrowableType tt
where
		(count(LoopStmt loop | isSource(loop) and isRetryLoop(loop) and isCaughtAndRetried(loop, tt) | loop) > 0 or
		count(LoopStmt loop | isSource(loop) and isRetryLoop(loop) and isNotRetried(loop, tt) | loop) > 0) and
		not isGenericJavaException(tt)
select appName() as app_name,
		tt.getQualifiedName() as exception_name,
		count(LoopStmt loop | isSource(loop) and isRetryLoop(loop) and isCaughtAndRetried(loop, tt) | loop) as num_locations_retried,
		count(LoopStmt loop | isSource(loop) and isRetryLoop(loop) and isNotRetried(loop, tt) | loop) as num_locations_not_retried,
		(num_locations_retried.(float)/(num_locations_retried+num_locations_not_retried)).maximum(num_locations_not_retried.(float)/(num_locations_retried+num_locations_not_retried)) as coherence,
		concat(LoopStmt loop | isSource(loop) and isRetryLoop(loop) and isCaughtAndRetried(loop, tt) | loop.getLocation().(GithubLocation).getGithubURL()+" "+getMethodList(loop,tt), " | ") as source_code_references_retried,
		concat(LoopStmt loop | isSource(loop) and isRetryLoop(loop) and isNotRetried(loop, tt) | loop.getLocation().(GithubLocation).getGithubURL()+" "+getMethodList(loop,tt), " | ") as source_code_references_not_retried
