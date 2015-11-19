{-# LANGUAGE RankNTypes, TupleSections #-}

{- This module is dedicated in infering the type of functions.
 - The type of a function consists of two separate parts:
 -
 - 1. The type of the arguments.
 - 2. The type of the return type.
 -
 - Currently, DuckTest cannot infer the return type,
 - however, DuckTest is able to infer the type of the arguments.
 -
 - DuckTest infers the type by looking at what other functions
 - the argument is passed to as well as observing the
 - attributes used by the function on that argument
 -}

module DuckTest.Infer.Functions (inferTypeForFunction) where

import Language.Python.Common
import DuckTest.Monad
import DuckTest.AST.Util
import DuckTest.AST.BinaryOperators

import Control.Monad

{- This function will take a Python function and infer the type
 - of this function. The type infered from this function is
 - of the type [args] -> return type. All the types are in a
 - structural format -}
inferTypeForFunction :: Statement a -> DuckTest a ([StructuralType], StructuralType)
inferTypeForFunction (Fun _ params _ body _) =

    {- Get a list of the names of the parameters to the function. For
     - each of those parameters, try to infer the type of each.
     -
     - Return type is not yet able to be inferred. This is a TODO -}
    let parameterIdentifiers :: [String]
        parameterIdentifiers = map (tryGetIdentifier "") params

        returnType = emptyType -- cannot yet infer return type
        in
        (,returnType) <$> mapM (`inferTypeForVariable`body) parameterIdentifiers


inferTypeForFunction _ =
    {- This function was called on something not a function -}
    die "inferTypeForFunction called on non function!"

{- Collects and infers the type of a variable name over
 - the span of the list of statements given. -}
inferTypeForVariable :: forall e. String -> [Statement e] -> DuckTest e StructuralType
inferTypeForVariable varname stmts =
    {- This function, we walk through each expression in the
     - body of statements. In each expression, we look to see
     - how the parameter is being used. -}
        mconcat <$> mapM observeExpr expressions
    where
        {- All of the expressions in the current body of
         - statements. We will fold through these and look
         - for when a function will be called -}
        expressions = allExpressions stmts

        observeExpr :: Expr a -> DuckTest a StructuralType
        {- An observation of the pattern `x.y` we use this
         - to infer that the argument `x` must have an attribute
         - `y` -}
        observeExpr (Dot (Var (Ident name _) _) (Ident attname _) _)
                     | name == varname =
                        verbose ("Found attribute usage: " ++ attname) >>
                        return (singletonType attname)

        {- An observation where we call a function with x as an argument.
         - We use this to retrieve more information about `x`. Specifically,
         - look up what `x` requires for this function to be valid.
         -
         - This observation is of function(..., x, ...)-}
        observeExpr ex@(Call (Var (Ident fnname _) pos) args _) = do

             mfn <- getFunction fnname

             case mfn of
                {- This function may not exist, we should warn, but
                 - then continue on with the type inference -}
                Nothing ->

                    iterateOverChildren ex

                {- This function does exist, so let us continue using
                 - normal type-checking routines -}
                Just (Function _ (paramsType, _)) -> do

                    when (length args > length paramsType) $
                        emitWarning ("Possible too many arguments for " ++ fnname) pos

                    let inferTypeFromArguments (expr', exprType) =
                            {- Iterate through the arguments to the observed
                             - function call. If the name alone is observed,
                             - then use infer the type for the argument, otherwise
                             - search for evidence in the expression -}
                            case getExpression expr' of

                                (Var (Ident nm _) _) | nm == varname ->
                                    return exprType

                                expr -> observeExpr expr

                    mconcatMapM inferTypeFromArguments (zip args paramsType)

        observeExpr (BinaryOp op (Var (Ident vname _) _) _ _)
                    | vname == varname = return $ singletonType (toDunderName op)

        observeExpr exp = iterateOverChildren exp

        {- infer through the child expressions of this expression -}
        iterateOverChildren exp = mconcatMapM observeExpr (subExpressions exp)

