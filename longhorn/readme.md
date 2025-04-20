after update using helm use below steps to remove unwanted pod/ds

kubectl get ds -n longhorn-system\n
kubectl delete ds engine-image-ei-51cc7b9c -n longhorn-system
kubectl get engineimages.longhorn.io -n longhorn-system\n
kubectl delete engineimages.longhorn.io ei-51cc7b9c -n longhorn-system
kubectl get engineimages.longhorn.io -n longhorn-system\n
kubectl delete pod -n longhorn-system --all\n