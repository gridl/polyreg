
##################################################################
# xvalPoly: generate mean absolute error of fitted models
##################################################################

# arguments:
#   for most args, see the comments for polyFit()
#   nHoldout: number of cases for the test set
#   yCol: if not NULL, Y is in this column, and will be moved to last
#   dropout: the proportion of columns of the polynomial matrix would be
#            randomly delected

# return: a vector of mean absolute error (for lm) or accuracy (for glm),
#         the i-th element of the list is for degree = i
#" @export

xvalPoly <- function(xy, maxDeg, maxInteractDeg=maxDeg, use="lm",
                     pcaMethod=NULL, pcaLocation=NULL, pcaPortion=0.9,
                     glmMethod="one",
                     nHoldout=min(10000, round(0.2 * nrow(xy))), stage2deg=NULL,
                     yCol=NULL, printTimes=TRUE, cls=NULL, dropout=0,
                     startDeg=1) {
  if (dropout >= 1) {
    stop("dropout should be less than 1.")
  }

  if (!is.null(yCol)) {
    xy <- moveY(xy, yCol)
  }

  if(nHoldout > nrow(xy)) {
    nHoldout <- round(0.2 * nrow(xy))
  }

  y <- xy[, ncol(xy)]
  if (is.factor(y)) {  # change to numeric code for the classes
     y <- as.numeric(y)
     xy[, ncol(xy)] <- y
  }

  # split input data into training and testing sets
  tmp <- splitData(xy, nHoldout)
  training <- tmp$trainSet
  testing <- tmp$testSet
  train.y <- training[, ncol(training)]
  train.x <- training[, -ncol(training)]
  test.y <- testing[, ncol(testing)]
  test.x <- testing[, -ncol(testing)]

  # compute accuracy of fit (via predict) for each degree up to maximum
  acc <- NULL
  for (i in 1:maxDeg) {  # for each degree
    # handle dropout of columns
    if (dropout != 0 && startDeg <= i) {
      ndropout <- floor(ncol(xy) * dropout)
      dropoutIdx <- sample(ncol(xy), ndropout, replace = FALSE)
      train1 <- cbind(train.x[, -dropoutIdx, drop=FALSE], train.y)
      test1 <- test.x[, -dropoutIdx, drop=FALSE]
    }
    else {
      train1 <- training
      test1 <- test.x
    }

    colnames(train1)[ncol(train1)] <- "y"

    # compute fit and predict based on fit
    pol <- polyFit(xy=train1, deg=i, use=use, pcaMethod=pcaMethod,
                   pcaLocation=pcaLocation, pcaPortion=pcaPortion,
                   glmMethod=glmMethod, cls=cls, dropout=0)
    pred <- predict(pol, test1)

    # store current degree's accuracy
    if (use == "lm") {
      acc[i] <- mean(abs(pred - test.y))
    } else {
      acc[i] <- mean(pred == test.y)
    }
  } # for each degree
  return(acc)
}

##################################################################
# xvalNnet: generate mean absolute error of fitted models
##################################################################

# xval for nnet package

# arguments and value:
#    see xvalPoly() above for most
#    classification is done if the Y variable is a factor
#    scaleXMat: if TRUE, apply scale() to predictor matrix
#    xy: as above, except that in classification case,
#        Y column of xy (last one, or yCol) must be a factor

# return: a vector of mean absolute error (for lm) or accuracy (for glm),
#         the i-th element of the list is for degree = i
#' @export

xvalNnet <- function(xy,size,linout, pcaMethod = FALSE,pcaPortion = 0.9,
                     scaleXMat=FALSE,nHoldout=min(10000,round(0.2*nrow(xy))),
                     yCol = NULL)
{
  require(nnet)
  ncxy <- ncol(xy)

  if(nHoldout > nrow(xy))
    nHoldout <- round(0.2*nrow(xy))

  if (!is.null(yCol)) xy <- moveY(xy,yCol)

  if (scaleXMat) xy <- scaleX(xy)  # only Xs are scaled
  tmp <- splitData(xy,nHoldout)
  training <- tmp$trainSet
  testingx <- tmp$testSet[,-ncxy]
  testingy <- tmp$testSet[,ncxy]


  yName <- names(xy)[ncol(xy)]
  cmd <- paste0('nnout <- nnet(',yName,' ~ .,data=training,size=')
  cmd <- paste0(cmd,size,',linout=',linout,')')
  eval(parse(text=cmd))
  preds <- predict(nnout,testingx)
  trainingy <- training[,ncxy]
  if (!is.factor(trainingy))  # regression case
    return(mean(abs(preds - testingy)))
  # classification case
  preds <- apply(preds,1,which.max)  # column numbers
  # convert to levels of Y
  preds <- levels(trainingy)[preds]
  return(mean(preds == testingy))
}

##################################################################
# xvalKf: generate mean absolute error of fitted models
##################################################################

# xval for nnet package

# arguments and value:
#    xy: as above, except that in classification case,
#        Y column of xy (last one, or yCol) must be a factor; otherwise
#        must NOT be a factor
#    nHoldout,yCol as above
#    units,activation,dropout: as in kms()

# examples:

# classification, 2 hidden layers, with 3rd layer for forming the
# predictions
# xvalKf(pe,units=c(15,15,NA),activation=c('relu','relu','softmax'),
#    dropout=c(0.1,0.1,NA)) 

# regression, 3 hidden layers, with 4th layer for forming the
# predictions
# xvalKf(pe,units=c(25,25,5,NA),activation=c('relu','relu','relu','linear'),
#    dropout=c(0.4,0.3,0.3,NA))

xvalKf <- function(xy,nHoldout=min(10000,round(0.2*nrow(xy))),yCol=NULL,
   units,activation,dropout)
{
  require(kerasformula)

  # build up the 'layers' argument for kms()
  u <- paste0('units=c(',paste0(units,collapse=','),')')
  a <- 'activation=c('
  for (i in 1:length(activation)) {
     ia <- activation[i]
     a <- paste0(a,'"',ia,'"')
     if (i < length(activation)) a <- paste0(a,',')
  }
  a <- paste0(a,')')
  d <- paste0('c(',paste0(dropout,collapse=','),')')
  layers <- paste0('layers=list(',u,',')
  layers <- paste0(layers,a,',')
  layers <- paste0(layers,d,',')
  layers <- paste0(layers,'use_bias = TRUE, kernel_initializer = NULL,')
  layers <- paste0(layers,'kernel_regularizer = "regularizer_l1",')
  layers <- paste0(layers,'bias_regularizer = "regularizer_l1",')
  layers <- paste0(layers,'activity_regularizer = "regularizer_l1")')

  if (is.null(yCol)) yCol <- ncol(xy)
  tmp <- splitData(xy,nHoldout)
  training <- tmp$trainSet
  testing <- tmp$testSet
  testingx <- tmp$testSet[,-yCol]
  testingy <- tmp$testSet[,yCol]

  yName <- names(xy)[yCol]
  trainingy <- training[,yCol]
  classcase <- is.factor(trainingy)
  # loss <- 'NULL'
  cmd <- 
     paste0('kfout <- kms(',yName,' ~ .,data=training,',layers,')')
  eval(parse(text=cmd))
  preds <- predict(kfout,testingx)$fit
  if (!classcase) {  # regression case
     ry <- range(trainingy)
     preds <- ry[1] + (ry[2]-ry[1]) * preds
     return(mean(abs(preds - testingy)))
  }
  # classification case
  return(mean(preds == testingy))
}


##################################################################
# kmswrapper: generate outputs/VIFs for each NNs layer
##################################################################

# arguments and value:
#     model: the object returned from keras_model_sequential()
#     x_test: the predictor variables of test set
#     y_test: the response variable of test set

# return: a list. Each element of the list is the output and VIF values
#         of each layer.

kmswrapper <- function(model, x_test, y_test) {
  require(car)
  result <- list()
  if (!is.null(dim(y_test))) {
    y <- apply(y_test, 1, which.max) # y_test has been to_categorical
  } else {
    y <- y_test
  }
    
  n <- length(model$layers)
  for (i in 1:n) {
    layer_model <- keras_model(inputs = model$input,
                               outputs = get_layer(model, index = i-1)$output)
    output <- predict(layer_model, x_test)
    df <- as.data.frame(cbind(y, output))
    vars <- paste(colnames(df)[-1], collapse = " + ")
    ff <- as.formula(paste("y", vars, sep = " ~ "))
    mod <- lm(ff, data=df)

    # check for perfect multicollinearity (exact linear relationship)
    # if perfect multicollinearity, vif() would cause error
    ld.vars <- attributes(alias(mod)$Complete)$dimnames[[1]]
    if (!is.null(ld.vars)) {
      print("Perfect Multicollinearity occurs! Following variables are omitted:")
      print(ld.vars)
      formula.new <- as.formula(
        paste(
          paste(deparse(ff), collapse=""),
          paste(ld.vars, collapse="-"),
          sep="-"
        )
      )
      mod <- lm(formula.new,data = df)
    }

    vifs <- vif(mod)
    result[[i]] <- list(output = output, vif = vifs)

  }
  return(result)
}

##################################################################
# xvalDNet: generate mean absolute error of fitted models
##################################################################

# xval for deepnet package, nn.*()

# arguments:
#    not all args of nn.train() are implemented here, e.g. dropout args
#       are missing
#    hidden: vector of number of units in each layer
#    output: final layer feeds into this; double quoted;
#            '"sig"m', '"linear"' or '"softmax"'
#    numepochs: number of epochs
#    pca*, scaleXMat,nHoldout,yCol: as above
#    x: predictor variables
#    y: Y; in classification case, must be a matrix of dummies

# value: mean abs. error

#' @export

xvalDnet <- function(x,y,hidden,output='"sigm"',numepochs=3,
                     pcaMethod = FALSE,pcaPortion = 0.9,
                     scaleXMat = TRUE,
                     nHoldout=min(10000,round(0.2*nrow(x))))
{
  require(deepnet)

  if (scaleXMat) x <- scale(x)

  tmp <- splitData(x,nHoldout,idxsOnly=TRUE)
  trainingx <- x[-tmp,]
  testingx <- x[tmp,]
  ym <- as.matrix(y)
  trainingy <- ym[-tmp,]
  testingy <- ym[tmp,]

  cmd <- paste0('nnout <- nn.train(trainingx,trainingy,')
  cmd <- paste0(cmd,'hidden=',hidden,',')
  cmd <- paste0(cmd,'output=',output,',')
  cmd <- paste0(cmd,'numepochs=',numepochs)
  cmd <- paste0(cmd,')')
  eval(parse(text=cmd))
  preds <- nn.predict(nnout,testingx)
  if (ncol(ym) == 1 & length(unique(ym)) > 2){  # regression case
    return(mean(abs(preds - testingy)))
  }else{
    if(length(unique(ym)) == 2){

      preds <- preds > mean(testingy) # assume mean(testingy) better latent threshold than 0.5
      return(mean(preds == testingy))

    }else{
      preds <- apply(preds,1,which.max)  # column numbers
      trueY <- apply(testingy,1,function(rw) which(rw == 1))
    }
    # convert to levels of Y
    return(mean(preds == trueY))
  }


}

######################  splitData() #################################
# support function, to split into training and test sets
##################################################################

splitData <- function(xy,nHoldout,idxsOnly=FALSE)
{
  n <- nrow(xy)
  ntrain <- nHoldout
  testIdxs <- sample(n, ntrain, replace = FALSE)
  if (idxsOnly) return(testIdxs)
  testSet <- xy[testIdxs,]
  trainSet <- xy[-testIdxs,]
  list(testSet=testSet,trainSet=trainSet)
}

######################  moveY() #################################
# support function, since getPoly() etc. require Y in last column
#################################################################

moveY <- function(xy,yCol)
{
  yName <- names(xy)[yCol]
  xy <- cbind(xy[,-yCol],xy[,yCol])
  names(xy)[ncol(xy)] <- yName
  xy
}

######################  scaleX() #################################
# support function, since NNs tend to like scaling
##################################################################

# xy consists of X columns followed by one Y column, maybe a factor,
# unless xOnly is TRUE, in which case xy is just the X columns
scaleX <- function(xy)
{
  ncxy <- ncol(xy)
  x <- xy[,-ncxy]
  x <- scale(x)
  xy[,-ncxy] <- x
  xy
}