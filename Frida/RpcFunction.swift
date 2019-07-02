import Foundation

@dynamicCallable
@dynamicMemberLookup
public struct RpcFunction {
    unowned let script: Script
    let functionName: String

    init(script: Script, functionName: String) {
        self.script = script
        self.functionName = functionName
        print("functionName: \(functionName)")
    }

    public func dynamicallyCall(withArguments args: [Any]) -> RpcRequest {
        return script.rpcPost(functionName: functionName,
                              requestId: script.nextRequestId, values: args)
    }

    public subscript(dynamicMember functionName: String) -> RpcFunction {
        get {
            return RpcFunction(script: script, functionName: "\(self.functionName).\(functionName)")
        }
    }
}

@dynamicCallable
public struct RpcFunctionSync<Result> {
    unowned let script: Script
    let functionName: String

    init(script: Script, functionName: String) {
        self.script = script
        self.functionName = functionName
    }

    public func dynamicallyCall(withArguments args: [Any]) throws -> Result {
        let untypedValue = try script.rpcPostSync(functionName: functionName,
                                                  requestId: script.nextRequestId, values: args)

        guard let value = untypedValue as? Result else {
            throw Error.rpcError(message: "Couldn't cast value \(String(describing: untypedValue)) to \(Result.self).", stackTrace: nil)
        }
        return value
    }
}
