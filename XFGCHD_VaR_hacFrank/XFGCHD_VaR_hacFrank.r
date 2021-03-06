############################# computation of VaR using HAC-Frank copula
rm(list = ls(all = TRUE))
graphics.off()

# please set working directory setwd('C:/...') setwd('~/...') #
# linux/mac os setwd('/Users/...') # windows

libraries = c("HAC", "CDVine", "fGarch", "foreach", "doParallel", "copula")
lapply(libraries, function(x) if (!(x %in% installed.packages())) {
    install.packages(x)
})
lapply(libraries, library, quietly = TRUE, character.only = TRUE)

############################# set up
eps1                = read.csv("eps1.csv")
sp.126              = read.csv("sp126.csv", header = T)[, -c(1, 2)]
p1                  = sp.126[-1, ]
p2                  = sp.126[-length(sp.126[, 1]), ]
l.r                 = 100 * log(p1/p2)
r                   = l.r
r1                  = r[, -c(1)]
r2                  = r1
dims                = 5
attach(r2)
r2                  = data.frame(cbind(AVB, EQR, TXN, ADI, LLY))
M                   = 1000
backtestNr          = 1000
VaR                 = matrix(NA, backtestNr, 4)
slidingWindowLength = 300
eps                 = matrix(NA, backtestNr, dim(r2)[2])
colnames(eps)       = colnames(r2)
eps1                = data.frame()
dat                 = eps1
paraMat             = list()
para                = matrix(NA, dims, 4)
sigma               = matrix(NA, backtestNr, dims)

############################# estimation GARCH parameter
cl     = makeCluster(37)
registerDoParallel(cl)
getDoParWorkers()
dat    = r2
datMat = list()

for (i in 1:backtestNr) {
    datMat[[i]] = dat[c(i:(i + (slidingWindowLength - 1))), 1:dims]
}
lengthPara  = 4
lengthEps1  = slidingWindowLength
lengthSigma = slidingWindowLength

objFun = function(dMat) {
    paraComb = list()
    library(fGarch)
    for (i in 1:dims) {
        fit           = garchFit(~garch(1, 1), data = dMat[[i]], trace = F)
        eps1.loop     = fit@residuals/fit@sigma.t
        para.loop     = fit@fit$coef
        sigma.loop    = fit@sigma.t
        lengthPara    = length(para.loop)
        paraComb[[i]] = c(para.loop, sigma.loop, eps1.loop)
    }
    return(paraComb)
}
resultD = foreach(dMat = datMat) %dopar% objFun(dMat)
stopCluster(cl)

############################# estimation of copula parameter
lengthPara  = 4 
lengthEps1  = slidingWindowLength  
lengthSigma = slidingWindowLength
totalLength = lengthPara + lengthEps1 + lengthSigma
epsComb     = list()
for (i in 1:backtestNr) {
    k            = pobs(as.data.frame(resultD[[i]]))
    epsComb[[i]] = k[-(1:(lengthPara + lengthEps1)), ] 
    
}
datMatEps = epsComb  

objFun = function(dMat) {
    library(HAC)
    colnames(dMat) = c("AVB", "EQR", "TXN", "ADI", "LLY")
    head(dMat)
    tree           = list(list(list("TXN", "ADI", 2.35), list("AVB", "EQR", 3.25), 
                          1.45), "LLY", 1.44)
    model          = hac(type = 5, tree = tree)
    result         = estimate.copula(dMat, hac = model, margins = "norm")  
    result
    plot(result, circles = 0.3, index = TRUE, l = 1.7)
    paraHAC        = get.params(result)
    paraHAC
    return(paraHAC)
}

ptm = proc.time()
cl  = makeCluster(37)
registerDoParallel(cl)  
getDoParWorkers()
resultDcopPara = foreach(dMat = datMatEps, .combine = "rbind") %dopar% 
                         objFun(dMat) 
stopCluster(cl)

############################# VaR computation
spread.real = read.csv("sp126.csv", header = T)[, -c(1:2)]  
attach(spread.real)
spread.real = data.frame(cbind(AVB, EQR, TXN, ADI, LLY))
S           = rowSums(spread.real)
S1          = S[-1]
S2          = S[-length(S)]
S3          = S2 - S1  
L.real      = S3[301:(300 + backtestNr)]
lengthPara  = 4  
lengthEps1  = slidingWindowLength  
lengthSigma = slidingWindowLength
totalLength = lengthPara + lengthEps1 + lengthSigma
para.vec    = resultDcopPara  
VaR         = matrix(NA, backtestNr, 4) 
datMatIndex = c(1:backtestNr)
objFunVaR   = function(dMat) {
    i                = dMat  
    library(HAC)
    para.EmployedHAC = para.vec[i, ]
    tree             = list(list(list("AVB", "EQR", para.EmployedHAC[4]), list("TXN", 
                            "ADI", para.EmployedHAC[3]), para.EmployedHAC[2]), "LLY", para.EmployedHAC[1])
    model            = hac(type = 5, tree = tree) 
    model
    u                = rHAC(M, model)
    u                = qnorm(u)  
    head(u)
    k                = as.data.frame(resultD[[i]])  
    k1               = k[c(1:lengthPara, lengthPara + lengthEps1, totalLength), ]  
    h                = sqrt(k1[2, ] + k1[3, ] * k1[lengthPara + 1, ]^2 * k1[lengthPara + 
                            2, ]^2 + k1[4, ] * k1[lengthPara + 1, ]^2)  
    k2               = matrix(NA, M, dims)
    k3               = matrix(NA, M, dims)
    k2[1, ]          = as.matrix(k1[1, ])  
    mu.t             = k2[rep(1, M), ]  
    k3[1, ]          = as.matrix(k1[lengthPara + 1, ])  
    sig.t            = k3[rep(1, M), ]  
    R                = mu.t + sig.t * u  
    spread           = spread.real 
    s1               = spread[i + (slidingWindowLength), ]     
    st               = data.frame(matrix(NA, M, dims))  
    st[1, ]          = s1
    st               = st[rep(1, M), ]
    L.sim            = matrix(NA, M, 1) 
    L.sim            = rowSums(st * (exp(0.01 * R) - 1))
    VaRt1005         = quantile(L.sim, 0.05)
    VaRt1001         = quantile(L.sim, 0.01)
    VaRt10005        = quantile(L.sim, 0.005)
    VaRt10001        = quantile(L.sim, 0.001)
    VaRt             = c(VaRt1005, VaRt1001, VaRt10005, VaRt10001)
    head(VaRt)
    return(VaRt)
}

cl         = makeCluster(37)
registerDoParallel(cl)  
getDoParWorkers()
resultVaR  = foreach(dMat = datMatIndex, .combine = "rbind") %dopar% objFunVaR(dMat)  
stopCluster(cl)
head(resultVaR)  
VaR        = resultVaR
resultComb = data.frame(L.real, VaR)


############################# exceeding ratio
Exceeding_Ratio = numeric(4)
for (alpha in 2:5) {
    nullVector = rep(0, backtestNr)
    for (i in 1:length(resultComb[, alpha])) {
        if (resultComb[, 1][i] < resultComb[, alpha][i]) {
            nullVector[i] = 1
        } else {
            nullVector[i] = 0
        }
    }
    Exceeding_Ratio[alpha] = sum(nullVector)/backtestNr
}
Exceeding_Ratio

############################# plot of VaR and quantile = 0.001
alpha           = 5
ptForPlot       = c(min(resultComb[, 1]), min(resultComb[, 2]), min(resultComb[, 
                  3]), min(resultComb[, 4]), min(resultComb[, 5]))
lowPt           = min(ptForPlot)
upPt            = max(resultComb[, 1])
Portfolio_Value = seq(lowPt, upPt, length.out = length(resultComb[, 1]))
Time_Index      = 1:length(seq(lowPt, upPt, length.out = length(resultComb[, 
                  1])))
plot(Time_Index, 
     Portfolio_Value, 
     col   = "white", 
     pch   = 19, 
     cex   = 0.5, 
     xlab  = "Time Index", 
     ylab  = "Profit and Loss of Portfolio")
lines(resultComb[, alpha], col = "gray", lwd = 6)

for (i in 1:length(resultComb[, alpha])) {
    if (resultComb[, 1][i] < resultComb[, alpha][i]) {
        points(i, lowPt + 1, col = "black", pch = 17, cex = 1.5)  
        points(i, resultComb[, 1][i], 
               col = "black", 
               pch = 3, 
               cex = 2.5, 
               lwd = 1)  
        points(i, resultComb[, 1][i], 
               col = "black", 
               pch = 5, 
               cex = 1.5, 
               lwd = 1) 
    } else {
        points(i, resultComb[, 1][i], 
               col = "black", 
               pch = 19, 
               cex = 1) 
    }
}







