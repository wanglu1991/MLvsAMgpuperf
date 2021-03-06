
library(ggplot2)
library(reshape2)
library(plyr)

cbbPalette <- gray(1:9/ 12)#c("red", "blue", "darkgray", "orange","black","brown", "lightblue","violet")
dirpath <- "~/Dropbox/Doctorate/svm-gpuperf/"
setwd(paste(dirpath, sep=""))

gpus <- read.table("./R-code/deviceInfo.csv", sep=",", header=T)
NoGPU <- dim(gpus)[1]

apps <- c("matMul_gpu_uncoalesced","matMul_gpu", "matMul_gpu_sharedmem_uncoalesced", "matMul_gpu_sharedmem",
         "matrix_sum_normal", "matrix_sum_coalesced", 
         "dotProd", "vectorAdd",  "subSeqMax")

flopsTheoreticalPeak <- gpus['max_clock_rate']*gpus['num_of_cores']
lambda <- matrix(nrow = NoGPU, ncol = length(apps), 0, dimnames = gpus['gpu_name'])

lambdaK40 <- c(4.30, 20, 19, 65 ,  2.50,  9.50,  9 , 10,  0.48)
lambdaK40L1 <- c(3.5,   20, 19,   65, 2.75,  9.5,    9,   10, 0.48)
lambdaGTX680 <- c(4.5,   19,   20,   68, 1.5,  9.25, 14, 11, 0.68)
lambdaTitan <- c(4.25,  21,   17,  50, 2.5, 10,  9.5,   12, 0.48)
lambdaK20 <- c(4.5,   21,   18,   52, 2.5,  9,  10, 10, 0.55)
lambdaQ <- c(4.75,   20,   20,   64, 1,  8.25, 11,  9.5, 0.55)
lambdaQL1 <- c(3.35, 20 , 25 , 64,  1.75,  8.5, 11 ,  9.50,  0.5)
lambdaTitanX <- c(9.5,   36,   36,  110, 3,  9.50,  8,  9.75, 0.95)
lambdaTitanBlack <- c(3.5,   17,   17,   52, 1.75,  7.5,  7.25,  8.5, 0.35)
lambdaTitanBlackL1 <- c(2.25,   17,   18,   52, 2,  7.5,  7.25,  8.5, 0.35)
lambdaGTX980 <- c(13,   44,   46,   120, 3.25,  9.5,  9,  9.5, 1.5)
lambdaGTX970 <- c(7,  26,  24, 80,   1.75,   10,  7,   6.5,   1.15)
lambdaGTX750 <- c(10,   52,   40,  138, 3.5, 14, 25, 15, 2)

lambda[1,] <- lambdaGTX680
lambda[2,] <- lambdaK40
lambda[3,] <- lambdaK20
lambda[4,] <- lambdaTitanBlack
lambda[5,] <- lambdaTitan
lambda[6,] <- lambdaQ
lambda[7,] <- lambdaGTX750
lambda[8,] <- lambdaTitanX
lambda[9,] <- lambdaGTX980
lambda[10,] <- lambdaGTX970

dataGPUsApps <- data.frame()

noSamples <- 10
for (k in c(1:6, 8:10)){

    TimeApp <- list()
    for (i in 1:length(apps)){
        data <- 0; Temp <- 0
        print(paste(" Loaded ", gpus[k,'gpu_name'], "/", apps[i], sep=""))
            for (j in 1:noSamples){
                temp <- read.table(paste("./data/", gpus[k,'gpu_name'],"/traces/run_", j, "/", apps[i], "-kernel-traces.csv", sep=""), sep=",", header=F)["V3"]
                data <- data + temp
            }
        
      TimeApp[apps[i]] <- data/noSamples
    }
    
    latencySharedMemory <- 5; #Cycles per processor
    latencyGlobalMemory <- latencySharedMemory* 100; #Cycles per processor
    
    latencyL1 <- latencySharedMemory; #Cycles per processor
    latencyL2 <- latencyGlobalMemory*0.5; #Cycles per processor
    
    SpeedupMatMul <- list()
    timeKernelMatMul <- list()
    for (i in 1:4){
        nN <- 9:13
        N <- 2^nN
        
        numberMultiplication <- N;
        
        tileWidth <- 16;
        threadsPerBlock <- tileWidth*tileWidth;
        
        gridsizes <- as.integer((N +  tileWidth -1)/tileWidth);
        blocknumber <- gridsizes*gridsizes
        numberthreads <- threadsPerBlock * blocknumber;
        
        reads <- numberthreads*N*2
        timeComputationKernel <- ((numberMultiplication * 1) ) * numberthreads;
        
        L1Effect <- 0
        L2Effect <- 0
        
        CommGM <- ((numberthreads*N*2 - L1Effect - L2Effect + numberthreads)*latencyGlobalMemory + L1Effect*latencyL1 + L2Effect*latencyL2);
        
        timeKernel <- ( lambda[k,i]^-1*(timeComputationKernel + CommGM)/(flopsTheoreticalPeak[k,]*10^6));
        timeKernelMatMul[[apps[i]]] <- timeKernel
        SpeedupMatMul[[apps[i]]] <- timeKernel[1:length(TimeApp[[apps[i]]])]/TimeApp[[apps[i]]];
    }
    SpeedupMatMul
    
    SpeedupMatSum <- list()
    timeKernelMatSum <- list()
    for (i in 5:6){
        
        nN <- 9:13
        N <- 2^nN
        
        
        gridsizes <- as.integer((N +  tileWidth -1)/tileWidth);
        blocknumber <- gridsizes*gridsizes
        numberthreads <- threadsPerBlock * blocknumber;
        numberMultiplication <- 1;
        
        reads <- numberthreads*2
        tempOperationcycles <- ((numberMultiplication * 10) ) * numberthreads;
        CommGM <- ((numberthreads*2 - L1Effect - L2Effect + numberthreads)*latencyGlobalMemory + L1Effect*latencyL1 + L2Effect*latencyL2);
        
        timeKernel <- ( lambda[k,i]^-1*(tempOperationcycles + CommGM)/(flopsTheoreticalPeak[k,]*10^6));
        timeKernelMatSum[[apps[i]]] <- timeKernel
        SpeedupMatSum[[apps[i]]] <- timeKernel[1:length(TimeApp[[apps[i]]])]/TimeApp[[apps[i]]];
    }
    SpeedupMatSum
    
    SpeedupVecOp <- list()
    timeKernelVecOp <- list()
    for (i in 7:9){
        if (gpus[k,'gpu_name'] == "GTX-750"){
            nN <- 18:26
            N <- 2^nN
        }
        else {
            nN <- 18:27
            N <- 2^nN
        }
        if (apps[i] != "subSeqMax"){
            
            BlockSize <- tileWidth*tileWidth
            blocknumber <- (N+BlockSize-1) / BlockSize ;
            
            numberthreads <- threadsPerBlock * blocknumber;
            numberMultiplication <- 1;
            
            reads <- numberthreads*2
            
            tempOperationcycles <- ((numberMultiplication * 20) ) * numberthreads;
            CommGM <- ((numberthreads*2 - L1Effect - L2Effect + numberthreads)*latencyGlobalMemory + L1Effect*latencyL1 + L2Effect*latencyL2);
            
        } else {
            
            gridsize <- 32;
            blocksize <- 128
            
            numberthreads <- gridsize * blocksize;
            N_perBlock <- N/gridsize;
            N_perThread <- N_perBlock/blocksize;
            
            numberMultiplication <- 1;
            
            reads <- numberthreads*N_perThread;
            
            tempOperationcycles <- 100*numberthreads * N_perThread;
            CommGM <- ((numberthreads*N_perThread - L1Effect - L2Effect + numberthreads*5)*latencyGlobalMemory + L1Effect*latencyL1 + L2Effect*latencyL2);
            CommSM <- (numberthreads*N_perThread + numberthreads*5)*latencySharedMemory
            
        }
        timeKernel <- ( lambda[k,i]^-1*(tempOperationcycles + CommGM)/(flopsTheoreticalPeak[k,]*10^6));
        timeKernelVecOp[[apps[i]]] <- timeKernel
        SpeedupVecOp[[apps[i]]] <- timeKernel[1:length(TimeApp[[apps[i]]])]/TimeApp[[apps[i]]];
        
    }
    SpeedupVecOp
    
    matMul <- array(unlist(SpeedupMatMul,use.names = T))
    TkmatMul <- array(unlist(timeKernelMatMul,use.names = T))
    
    nN <- 9:13
    N <- 2^nN
    
    namesMatMul <- c(rep("matMul_gpu_uncoalesced",length(N)), rep("matMul_gpu",length(N)),
                     rep("matMul_gpu_sharedmem_uncoalesced",length(N)), rep("matMul_gpu_sharedmem",length(N)))
    
    dfmatMul <- cbind(matMul, TkmatMul, namesMatMul, N)

    matSum <- array(unlist(SpeedupMatSum,use.names = T))
    TkmatSum <- array(unlist(timeKernelMatSum,use.names = T))
    nN <- 9:13
    N <- 2^nN
    
    namesmatSum <- c(rep("matrix_sum_normal",length(N)), rep("matrix_sum_coalesced",length(N)))
    
    dfmatSum <- cbind(matSum, TkmatSum, namesmatSum, N)
    
    matVecOp <- array(unlist(SpeedupVecOp,use.names = T))
    TkVecop <- array(unlist(timeKernelVecOp,use.names = T))
    
    if (gpus[k,'gpu_name'] == "GTX-750"){
        nN <- 18:26
        N <- 2^nN
    }
    else {
        nN <- 18:27
        N <- 2^nN
    }
    
    namesVecOp <-c(rep("dotProd",length(N)), rep("vectorAdd",length(N)),  rep("subSeqMax",length(N)))
    dfVecOp <- cbind(matVecOp, TkVecop, namesVecOp,N)
    
    allApp = rbind(dfmatMul,dfmatSum,dfVecOp)
    
    dfAllApp <- data.frame(Gpus=gpus[k,'gpu_name'], Apps=allApp[,3], InputSize=allApp[,4], ThreadBlock=0, Measured= array(unlist(TimeApp,use.names = F)), Predicted=allApp[,2], accuracy=allApp[,1], Min=0, max=0, Mean=0, Median=0, SD=0, mse=0, mae=0, mape=0)
    
    dataGPUsApps <- rbind(dfAllApp, dataGPUsApps)
    
}

dataTemp <- data.frame()

dataTemp <- dataGPUsApps

dataTemp$Apps <- factor(dataTemp$Apps, levels =  c("matMul_gpu_uncoalesced","matMul_gpu", "matMul_gpu_sharedmem_uncoalesced", "matMul_gpu_sharedmem",
                                                   "matrix_sum_normal", "matrix_sum_coalesced", 
                                                 "dotProd", "vectorAdd",  "subSeqMax"))

dataTemp$Apps <- revalue(dataTemp$Apps, c("matMul_gpu_uncoalesced"="matMul_GM_uncoalesced", "matMul_gpu"="matMul_GM_coalesced", 
                         "matMul_gpu_sharedmem_uncoalesced"="matMul_SM_uncoalesced", "matMul_gpu_sharedmem"="matMul_SM_coalesced",
                         "matrix_sum_normal"="matrix_sum_uncoalesced"))

dataTemp$Gpus <- factor(dataTemp$Gpus, levels = c("Tesla-K40",  "Tesla-K20", "Quadro", "Titan", "TitanBlack", "TitanX", "GTX-680","GTX-980",    "GTX-970",    "GTX-750"))

dataTemp$InputSize <- as.numeric(as.character(dataTemp$InputSize))
dataTemp$accuracy <- as.numeric(as.character(dataTemp$accuracy))

Result_AM <- dataTemp
Graph <- ggplot(data=dataTemp, aes(x=Gpus, y=accuracy, group=Gpus, col=Gpus)) + 
    geom_boxplot(size=1.5, outlier.size = 2.5) + scale_y_continuous(limits =  c(0, 2.5)) +
    stat_boxplot(geom ='errorbar') +
    xlab(" ") + 
    theme_bw() +
    ggtitle("Accuracy of the BSP-based Analytical model") +
    ylab(expression(paste("Accuracy ",T[k]/T[m] ))) +
    theme(plot.title = element_text(family = "Times", face="bold", size=30)) +
    theme(axis.title = element_text(family = "Times", face="bold", size=20)) +
    theme(axis.text  = element_text(family = "Times", face="bold", size=20, colour = "Black")) +
    theme(axis.text.x=element_blank()) +
    theme(legend.title  = element_text(family = "Times", face="bold", size=0)) +
    theme(legend.text  = element_text(family = "Times", face="bold", size=20)) +
    theme(legend.direction = "horizontal", 
          legend.position = "bottom",
          legend.key=element_rect(size=5),
          legend.key.size = unit(3, "lines")) +
    # facet_grid(.~Apps, scales="fixed") 
    facet_wrap(~Apps, ncol=3, scales="fixed") +
    theme(strip.text = element_text(size=20))+
    scale_colour_grey()


ggsave(paste("./images/ResultModel/ResutAnalyticalModel.pdf",sep=""), Graph, device = pdf, height=10, width=16)
# ggsave(paste("./images/ResultModel/ResutAnalyticalModel.png",sep=""), Graph,height=10, width=16)


lambda <- data.frame(lambda)
colnames(lambda) <- apps
lambda[-c(7), ]
lambdaT <- data.frame()
lambdaT <- rbind(lambdaT,data.frame(apps=rep("MMGU"), lambdas=lambda$matMul_gpu_uncoalesced))
lambdaT <- rbind(lambdaT,data.frame(apps=rep("MMGC"), lambdas=lambda$matMul_gpu))
lambdaT <- rbind(lambdaT,data.frame(apps=rep("MMSU"), lambdas=lambda$matMul_gpu_sharedmem_uncoalesced))
lambdaT <- rbind(lambdaT,data.frame(apps=rep("MMSC"), lambdas=lambda$matMul_gpu_sharedmem))
lambdaT <- rbind(lambdaT,data.frame(apps=rep("MAU"), lambdas=lambda$matrix_sum_normal))
lambdaT <- rbind(lambdaT,data.frame(apps=rep("MAC"), lambdas=lambda$matrix_sum_coalesced))
lambdaT <- rbind(lambdaT,data.frame(apps=rep("dotP"), lambdas=lambda$dotProd))
lambdaT <- rbind(lambdaT,data.frame(apps=rep("vAdd"), lambdas=lambda$vectorAdd))
lambdaT <- rbind(lambdaT,data.frame(apps=rep("MSA"), lambdas=lambda$subSeqMax))

Graph <- ggplot(data=lambdaT, aes(x=apps, y=lambdas, group=apps, col=apps)) + 
    scale_y_continuous(breaks = round(seq(0, max(lambdaT$lambdas), by = 10),1)) +
    geom_boxplot(size=1.5, outlier.size = 2.5) + 
    stat_boxplot(geom ='errorbar') +
    xlab("Applications ") + 
    ggtitle("Lambda Values of each one of the Applications") +
    ylab("Lambda Values") +
    theme(plot.title = element_text(family = "Times", face="bold", size=30)) +
    theme(axis.title = element_text(family = "Times", face="bold", size=20)) +
    theme(axis.text  = element_text(family = "Times", face="bold", size=20, colour = "Black")) +
    theme(legend.position = "none") +
    theme(strip.text = element_text(size=20))
# Graph
ggsave(paste("./images/ResultModel/LambdaAnalyticalModel.pdf",sep=""), Graph, device = pdf, height=10, width=16)