# DTU31761A3: Wind Power Output Prediction using Regression
# author: Edward J. Xu
# date: May 22th, 2019
# version: 3.6
# setwd("~/Documents/Github/WindPowerPrediction")
########################################################################################################################
rm(list = ls())
library(lubridate)
########################################################################################################################
cat("#### 0,  Control Parameters, Data and Functions ################################\n") ##############################
## 0.1,  Control Parameters 1
numFold      <- 10   # [number of folds for cross validation]
outputSeries <- 11   # [series number of the output file]
wheOutput    <- T    # [whether to output the results]
wheVali      <- T    # [whether to validate the result]
numConCoef   <- 360  # [number of concentration coefficients]
numIte       <- 1    # [number of further iterations] if = 1, there is no further iteration to optimize the coeffcients.
if (numIte > 1) {
    wheFurIte <- T
} else {
    wheFurIte <- F    # [whether do further iterations]
}
## 0.2, Name of the data files
strNameTrain <- "Data/TrainData3.csv"
strNamePred  <- "Data/WeatherForecastInput3.csv"
strNameVali  <- "Data/TrainData4.csv"  # Data for validation is the tail data in training data in next session
source("Data.R")  # All functions needed for Data.R is in FuncData.R
## 0.3, Function Files
source("FuncCrossVali.R")
source("FuncLocalReg.R")
source("FuncSeasonAdap.R")
source("FuncWindDirec.R")
if (wheOutput) {
    source("FuncOutput.R")
}
## 0.4,  Control Parameters 2
deltaKernalSeasonPred <- numPred / 2  # will set the center of prediction period as the main season.
# [forward value of kernalSeasonPred] If 10, means kernalSeasonPred = numTrain + 10.
cat("################################################################################\n") ##############################
cat("#### 1/6,  vecKernal and matWeight for Local Regression ########################\n")
source("PreLocalReg.R")
cat("################################################################################\n") ##############################
cat("#### 2/6,  Prepare Seasonal Adaptive Models ####################################\n")
source("PreSeasonAdap.R")
cat("################################################################################\n") ##############################
cat("#### 3/6,  Cross Validation to Find Optimal Con-Coef for Wind Direction ########\n")
cat("---- 3.1,  Benchmark without Con-Coef ------------------------------------------\n")
mrmseBenchmark <- crossValid(vecKernal, listVecKernalValue, datfTrain, 10)
cat("armseBenchmark =", mrmseBenchmark, "\n")
cat("---- 3.2,  First Iteration -----------------------------------------------------\n")
listResult <- optimWindDirection(listVecKernalValue, vecKernalSeason, numConCoef, datfTrain)
vecCoef <- listResult$par
vecObj <- listResult$obj
rm(listResult)
if (wheOutput) {
    outputResult(vecCoef, outputSeries)
}
cat("aveARMSE = ", (sqrt(sum((vecObj - mrmseBenchmark)^2)) / numConCoef * 100), "%\n", sep = "")
# The calculation of averaged improvement is the same as mse
cat("--------------------------------------------------------------------------------\n") # ----------------------------
# 3.2,  Further Iterations
if (wheFurIte) {
    cat("---- 3.3,  Further Iterations --------------------------------------------------\n")
    # Store all the results from first iteration
    matCoef <- matrix(1, nrow = numIte, ncol = numConCoef)
    matCoef[1,] <- vecCoef
    matObj <- matrix(1, nrow = numIte, ncol = numConCoef)
    matObj[1,] <- vecObj
    listListVecKernalValue <- vector("list", numIte)
    listListVecKernalValue[[1]] <- listVecKernalValue
    # Begin further iteration
    for (ite in 2:numIte) {
        cat("----", ite, "-th Iteration ---------------------------------------------------\n", sep = "")
        # The speed.center should be updated before every further iteration
        datfTrain$speed.center <- updateWindSpeedCenter(matCoef[(ite - 1),], datfTrain, numConCoef)
        datfPred$speed.center <- updateWindSpeedCenter(matCoef[(ite - 1),], datfPred, numConCoef)
        listListVecKernalValue[[ite]] <- calListVecKernalValue(listMatWeightSeason, datfTrain)
        listResult <- optimWindDirection(listListVecKernalValue[[ite]], vecKernalSeason, numConCoef, datfTrain)
        matCoef[ite, 1:length(listResult$par)] <- listResult$par
        matObj[ite, 1:length(listResult$obj)] <- listResult$obj
        cat("aveARMSE = ", (sqrt(sum((matObj[ite] - mrmseBenchmark)^2)) / numConCoef * 100), "%\n", sep = "")
        # cat("vecCoef = [", paste(matCoef[ite,], collapse = ", "), "]\n", sep = "")  # It's too long to print
        cat("--------------------------------------------------------------------------------\n")
    }; rm(listResult, ite)
    if (wheOutput) {
        outputResult(matCoef, outputSeries)
    }
    ## 3.3,  Get vecCoefProduct ----------------------------------------------------------------------------------------
    # The final optimal coefficient for every degree are the product of every iteration.
    vecCoefProduct <- rep(1, numConCoef)
    for (i in 1:numIte) {
        for (j in 1:numConCoef) {
            vecCoefProduct[j] <- vecCoefProduct[j] * matCoef[i, j]
        }
    }
    # Because the speed.center is updated during further iterations, it must be reset before update by vecCoefProduct.
    # It's more clear to update in the following section.
    datfTrain$speed.center <- datfTrain$speed.norm
    datfPred$speed.center <- datfPred$speed.norm
}
cat("################################################################################\n") ##############################
cat("#### 4/6,  SALR Model and Centered Wind Speed ##################################\n")
## 4.1,  Center the wind speed using optimal par from wind direction model
if (wheFurIte) {
    datfTrain$speed.center <- updateWindSpeedCenter(vecCoefProduct, datfTrain, numConCoef)
    datfPred$speed.center <- updateWindSpeedCenter(vecCoefProduct, datfPred, numConCoef)
} else {
    datfTrain$speed.center <- updateWindSpeedCenter(vecCoef, datfTrain, numConCoef)
    datfPred$speed.center <- updateWindSpeedCenter(vecCoef, datfPred, numConCoef)
}
## 4.2,  Kernal for Adaptive Seasonal Local Rregression
kernalSeasonPred <- numTrain + deltaKernalSeasonPred  # [kernal of seasonal adaptive local regression]
cat("kernalSeasonPred = ", kernalSeasonPred, "\n", sep = "")
matWeightSeasonPred <- calMatWeightSeasonGaussian(matWeight, datfTrain$series, kernalSeasonPred)
## 4.3,  Calculate Kernal value
vecKernalValuePred <- calVecKernalValue(matWeightSeasonPred, datfTrain)
if (wheOutput) {
    outputResult(vecKernalValuePred, outputSeries)
}
cat("--------------------------------------------------------------------------------\n")
cat("vecKernalValuePred = [", paste(vecKernalValuePred, collapse = ", "), "]\n", sep = "")
cat("################################################################################\n") ##############################
cat("#### 5/6,  Prediction ##########################################################\n")
vecPowerPred <- predLinearInter(datfPred$speed.center, vecKernal, vecKernalValuePred)
if (wheOutput) {
    outputResult(vecPowerPred, outputSeries)
}
if (wheVali) {
    rmse <- calPredictionRMSE(vecPowerPred, datfVali$power)
    cat("Validation Result: rootMeanSquaredError = ", rmse, "%\n", sep = "")
}
cat("#### Calculation End ###########################################################\n") ##############################
